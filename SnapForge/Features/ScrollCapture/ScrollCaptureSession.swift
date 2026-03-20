import AppKit
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Orchestrates the scroll capture lifecycle — coordinates engine, UI panels, and scroll simulation.
@MainActor
final class ScrollCaptureSession {

    // MARK: - Public Interface

    /// Called on completion with the preview image and an optional pre-saved URL.
    /// For multi-frame scroll captures, the URL is already saved (bypasses TIFF pipeline).
    var onComplete: ((_ image: NSImage, _ savedURL: URL?) -> Void)?
    var onCancel: (() -> Void)?

    // MARK: - Private State

    private let captureRect: CGRect
    private let engine = ScrollCaptureEngine()

    private var state: ScrollCaptureState = .ready
    private var frames: [CGImage] = []
    private var overlaps: [Int] = []
    private var autoScrollTask: Task<Void, Never>?
    private var escMonitor: Any?
    private var globalEscMonitor: Any?
    private var scrollMonitor: Any?
    private var clickMonitor: Any?
    private var moveMonitor: Any?
    private var scrollCaptureTimer: Timer?
    private var showHeightWarning = false

    // UI panels
    private var bracketWindow: ScrollCaptureBracketWindow?
    private var toolbarPanel: ScrollCaptureToolbarPanel?
    private var previewPanel: ScrollCapturePreviewPanel?
    private var helpPanel: ScrollCaptureHelpPanel?

    // Scroll configuration
    private let scrollInterval: TimeInterval = 0.10  // 100ms between scroll events (~10 lines/sec)
    private let captureInterval: UInt64 = 350_000_000  // 350ms between frame captures
    private var continuousScrollTimer: Timer?
    private let maxFrames = 50
    private let maxStitchedHeight = 30_000  // Max output height in pixels (at 1x) to prevent OOM
    private let heightWarningThreshold = 15_000  // Show warning above this height (1x pixels)
    private let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0

    /// Collect window IDs of our UI panels to exclude from screen capture
    private var uiWindowIDs: [CGWindowID] {
        var ids: [CGWindowID] = []
        if let wn = bracketWindow?.windowNumber, wn > 0 { ids.append(CGWindowID(wn)) }
        if let wn = toolbarPanel?.windowNumber, wn > 0 { ids.append(CGWindowID(wn)) }
        if let wn = previewPanel?.windowNumber, wn > 0 { ids.append(CGWindowID(wn)) }
        if let wn = helpPanel?.windowNumber, wn > 0 { ids.append(CGWindowID(wn)) }
        return ids
    }

    // MARK: - Init

    init(captureRect: CGRect) {
        self.captureRect = captureRect
    }

    // MARK: - Lifecycle

    func show() {
        let screenHeight = NSScreen.main?.frame.height ?? 1080
        let nsRect = CGRect(
            x: captureRect.origin.x,
            y: screenHeight - captureRect.origin.y - captureRect.height,
            width: captureRect.width,
            height: captureRect.height
        )

        bracketWindow = ScrollCaptureBracketWindow(captureRect: nsRect)
        bracketWindow?.makeKeyAndOrderFront(nil)

        toolbarPanel = ScrollCaptureToolbarPanel()
        refreshToolbar()

        previewPanel = ScrollCapturePreviewPanel()
        previewPanel?.show(toRightOf: captureRect, image: nil, frameCount: 0)

        installEscMonitor()
        print("📐 Scroll capture: session started for \(captureRect)")
    }

    func dismiss() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
        removeEscMonitor()
        stopScrollMonitor()
        stopAutoScrollMonitors()
        stopContinuousScroll()

        bracketWindow?.orderOut(nil)
        bracketWindow = nil
        toolbarPanel?.dismiss()
        toolbarPanel = nil
        previewPanel?.dismiss()
        previewPanel = nil
        helpPanel?.dismiss()
        helpPanel = nil

        frames.removeAll()
        overlaps.removeAll()
    }

    // MARK: - ESC Key

    private func installEscMonitor() {
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancel()
                return nil
            }
            return event
        }
        globalEscMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor [weak self] in
                    self?.cancel()
                }
            }
        }
    }

    private func removeEscMonitor() {
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
        if let m = globalEscMonitor { NSEvent.removeMonitor(m); globalEscMonitor = nil }
    }

    // MARK: - Scroll Event Monitor (Manual Scroll)

    /// Monitor global scroll events — when user scrolls manually, auto-capture after they stop.
    private func startScrollMonitor() {
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleUserScroll()
            }
        }
        print("👂 Scroll monitor: listening for manual scroll events")
    }

    private func stopScrollMonitor() {
        if let m = scrollMonitor { NSEvent.removeMonitor(m); scrollMonitor = nil }
        scrollCaptureTimer?.invalidate()
        scrollCaptureTimer = nil
    }

    /// Called each time user scrolls — debounce and capture after scrolling stops.
    private func handleUserScroll() {
        guard state == .capturing else { return }

        // Reset the debounce timer on each scroll event
        scrollCaptureTimer?.invalidate()
        scrollCaptureTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.captureOneFrame()
            }
        }
    }

    // MARK: - Actions

    /// Capture first frame, start scroll monitor for manual mode, enter capturing state.
    private func startCapture() {
        guard state == .ready else { return }
        state = .capturing
        refreshToolbar()
        captureOneFrame()

        // Start listening for manual scroll events
        startScrollMonitor()
    }

    /// Manually capture one additional frame
    private func captureFrame() {
        guard state == .capturing else { return }
        captureOneFrame()
    }

    /// Auto-scroll mode
    private func startAutoScroll() {
        stopScrollMonitor()  // Pause scroll monitor during auto-scroll

        if frames.isEmpty {
            Task { [weak self] in
                guard let self else { return }
                await self.captureOneFrameAsync()
                self.beginAutoScrollLoop()
            }
            return
        }
        beginAutoScrollLoop()
    }

    private func beginAutoScrollLoop() {
        state = .autoScrolling
        refreshToolbar()
        startAutoScrollMonitors()

        let scrollPoint = CGPoint(x: captureRect.midX, y: captureRect.midY)

        // Start CONTINUOUS scrolling — timer posts -1 line every 40ms without stopping.
        // This runs independently from frame captures, creating smooth uninterrupted scrolling.
        startContinuousScroll(at: scrollPoint)

        // Separate async loop captures frames periodically while the scroll timer runs.
        autoScrollTask = Task { [weak self] in
            guard let self else { return }

            // Brief initial delay for scroll to start
            try? await Task.sleep(nanoseconds: 200_000_000)

            var consecutiveIdentical = 0

            while !Task.isCancelled, self.state == .autoScrolling, self.frames.count < self.maxFrames {
                // Check projected height before capturing more
                let currentHeight = self.projectedHeight()
                if currentHeight >= self.maxStitchedHeight {
                    print("📏 Scroll capture: max height cap reached (\(self.maxStitchedHeight)px)")
                    self.stopContinuousScroll()
                    self.state = .capturing
                    refreshToolbar()
                    startScrollMonitor()
                    break
                }

                // Update height warning state
                let shouldWarn = currentHeight >= self.heightWarningThreshold
                if shouldWarn != self.showHeightWarning {
                    self.showHeightWarning = shouldWarn
                    refreshToolbar()
                }

                guard !Task.isCancelled, self.state == .autoScrolling else { break }

                do {
                    let rawFrame = try await engine.captureFrame(rect: captureRect, excludeWindowIDs: uiWindowIDs)

                    // Downscale from Retina 2x to 1x immediately to save memory
                    let newFrame: CGImage
                    if scaleFactor > 1.0, let downscaled = ScrollCaptureEngine.downscale(rawFrame, by: scaleFactor) {
                        newFrame = downscaled
                    } else {
                        newFrame = rawFrame
                    }

                    if let lastFrame = frames.last, engine.framesAreIdentical(lastFrame, newFrame, threshold: 0.95) {
                        consecutiveIdentical += 1
                        if consecutiveIdentical >= 2 {
                            print("📍 Scroll capture: end of content (\(frames.count) frames)")
                            self.stopContinuousScroll()
                            self.state = .capturing
                            refreshToolbar()
                            startScrollMonitor()
                            break
                        }
                    } else {
                        consecutiveIdentical = 0

                        let overlap = frames.isEmpty ? 0 : engine.detectOverlap(
                            previous: frames.last!, current: newFrame
                        )

                        frames.append(newFrame)
                        if frames.count > 1 {
                            overlaps.append(overlap)
                        }

                        refreshPreview()
                        refreshToolbar()
                        print("📸 Scroll capture: frame \(frames.count) (overlap: \(overlap)px, 1x)")
                    }
                } catch {
                    print("❌ Scroll capture: frame failed: \(error)")
                    break
                }

                // Wait before next capture — scroll timer continues running during this sleep
                try? await Task.sleep(nanoseconds: captureInterval)
            }

            if self.state == .autoScrolling {
                self.stopContinuousScroll()
                self.state = .capturing
                refreshToolbar()
                startScrollMonitor()
            }
        }
    }

    // MARK: - Continuous Scroll Timer

    /// Starts a repeating timer that posts -1 line scroll events continuously.
    /// This runs independently from frame captures so scrolling never pauses.
    private func startContinuousScroll(at point: CGPoint) {
        stopContinuousScroll()
        continuousScrollTimer = Timer.scheduledTimer(withTimeInterval: scrollInterval, repeats: true) { _ in
            if let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 1,
                wheel1: -1,
                wheel2: 0,
                wheel3: 0
            ) {
                event.location = point
                event.post(tap: .cghidEventTap)
            }
        }
    }

    /// Stops the continuous scroll timer.
    private func stopContinuousScroll() {
        continuousScrollTimer?.invalidate()
        continuousScrollTimer = nil
    }

    private func pauseAutoScroll() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
        stopContinuousScroll()
        stopAutoScrollMonitors()
        state = .paused
        refreshToolbar()
        startScrollMonitor()
    }

    // MARK: - Auto-Scroll Interaction Monitors

    /// Start all monitors needed during auto-scroll: click + mouse movement.
    private func startAutoScrollMonitors() {
        stopAutoScrollMonitors()

        // Global left-click monitor — pauses auto-scroll when user clicks anywhere.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.state == .autoScrolling else { return }
                print("🖱️ Scroll capture: click detected — pausing auto-scroll")
                self.pauseAutoScroll()
            }
        }

        // Global mouse-moved monitor — pauses when cursor moves above capture area
        // or near the top of the screen (within 50px). Fires in real-time on every
        // mouse movement, much more responsive than polling in the scroll loop.
        let captureTopCG = captureRect.origin.y  // CG: Y of top edge of capture area
        moveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            // Read mouse position directly (synchronous, thread-safe)
            let mouseNS = NSEvent.mouseLocation
            let screenHeight = NSScreen.main?.frame.height ?? 1080
            let mouseY_CG = screenHeight - mouseNS.y

            // Pause if mouse is above capture area OR within top 50px of screen
            let isAboveCaptureArea = mouseY_CG < captureTopCG
            let isNearTopOfScreen = mouseY_CG < 50

            if isAboveCaptureArea || isNearTopOfScreen {
                Task { @MainActor [weak self] in
                    guard let self, self.state == .autoScrolling else { return }
                    print("🖱️ Scroll capture: mouse moved to top — pausing auto-scroll")
                    self.pauseAutoScroll()
                }
            }
        }
    }

    /// Stop all auto-scroll interaction monitors.
    private func stopAutoScrollMonitors() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        if let monitor = moveMonitor {
            NSEvent.removeMonitor(monitor)
            moveMonitor = nil
        }
    }

    // MARK: - Mouse Position Check

    /// Check if the mouse cursor is currently above the capture area (CG coordinates).
    /// Uses direct polling of NSEvent.mouseLocation — more reliable than event monitors.
    private func isMouseAboveCaptureArea() -> Bool {
        let mouseNS = NSEvent.mouseLocation
        let screenHeight = NSScreen.main?.frame.height ?? 1080
        // Convert NS coords (bottom-left origin) → CG coords (top-left origin)
        let mouseY_CG = screenHeight - mouseNS.y
        // In CG coords, smaller Y = higher on screen. captureRect.origin.y is the top edge.
        return mouseY_CG < captureRect.origin.y
    }

    private func finish() {
        guard !frames.isEmpty else { cancel(); return }

        print("✅ Scroll capture: finishing with \(frames.count) frames, \(overlaps.count) overlaps")

        if frames.count == 1 {
            // Single frame — small enough for the normal save pipeline
            let image = NSImage(
                cgImage: frames[0],
                size: NSSize(width: CGFloat(frames[0].width), height: CGFloat(frames[0].height))
            )
            dismiss()
            onComplete?(image, nil)
            return
        }

        // Multi-frame: save directly as PNG to bypass TIFF intermediary
        guard let result = saveDirectlyAsPNG() else {
            print("❌ Scroll capture: direct save failed, falling back to standard pipeline")
            // Fallback: use the standard stitchFrames path
            if let stitched = engine.stitchFrames(frames, overlaps: overlaps) {
                dismiss()
                onComplete?(stitched, nil)
            } else {
                dismiss()
            }
            return
        }

        dismiss()
        onComplete?(result.previewImage, result.savedURL)
    }

    private func cancel() {
        dismiss()
        onCancel?()
    }

    // MARK: - Frame Capture Helpers

    private func captureOneFrame() {
        Task { [weak self] in
            await self?.captureOneFrameAsync()
        }
    }

    private func captureOneFrameAsync() async {
        // Check max height cap
        if projectedHeight() >= maxStitchedHeight {
            print("📏 Scroll capture: max height cap reached (\(maxStitchedHeight)px)")
            return
        }

        do {
            let rawFrame = try await engine.captureFrame(rect: captureRect, excludeWindowIDs: uiWindowIDs)

            // Downscale from Retina 2x to 1x immediately
            let newFrame: CGImage
            if scaleFactor > 1.0, let downscaled = ScrollCaptureEngine.downscale(rawFrame, by: scaleFactor) {
                newFrame = downscaled
            } else {
                newFrame = rawFrame
            }

            // Skip duplicate frames — if content hasn't scrolled, don't add the same frame again
            if let lastFrame = frames.last, engine.framesAreIdentical(lastFrame, newFrame, threshold: 0.95) {
                print("⏭️ Scroll capture: skipping duplicate frame (content hasn't scrolled)")
                return
            }

            let overlap: Int
            if let lastFrame = frames.last {
                overlap = engine.detectOverlap(previous: lastFrame, current: newFrame)
            } else {
                overlap = 0
            }

            frames.append(newFrame)
            if frames.count > 1 {
                overlaps.append(overlap)
            }

            refreshPreview()
            refreshToolbar()
            print("📸 Scroll capture: frame \(frames.count) captured (overlap: \(overlap)px, 1x)")
        } catch {
            print("❌ Scroll capture: capture failed: \(error)")
        }
    }

    // MARK: - Direct PNG Save

    /// Calculate projected total height of all frames minus overlaps.
    private func projectedHeight() -> Int {
        guard !frames.isEmpty else { return 0 }
        var height = frames[0].height
        for i in 1..<frames.count {
            let overlap = i - 1 < overlaps.count ? overlaps[i - 1] : 0
            height += frames[i].height - overlap
        }
        return height
    }

    /// Save the stitched CGImage directly as PNG using CGImageDestination.
    /// Bypasses NSImage.tiffRepresentation entirely — the key optimization.
    private func saveDirectlyAsPNG() -> (previewImage: NSImage, savedURL: URL)? {
        guard let cgImage = engine.stitchFramesToCGImage(frames, overlaps: overlaps) else {
            print("❌ Scroll capture: stitchFramesToCGImage failed")
            return nil
        }

        let storage = AppEnvironment.shared.storageService
        let dir = storage.snapForgeDirectory
        let access = SandboxFileAccessManager.shared.beginAccessingURL(dir)
        defer { access.stop() }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let filename = storage.generateImageFilename(format: "png")
        let url = dir.appendingPathComponent(filename)

        // Write directly as PNG using CGImageDestination — no TIFF intermediary
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            print("❌ Scroll capture: failed to create CGImageDestination")
            return nil
        }

        CGImageDestinationAddImage(destination, cgImage, nil)

        guard CGImageDestinationFinalize(destination) else {
            print("❌ Scroll capture: failed to finalize PNG")
            return nil
        }

        // Log file size
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int {
            let mb = Double(size) / 1_048_576.0
            print("✅ Scroll capture: saved \(String(format: "%.1f", mb))MB PNG → \(url.lastPathComponent)")
        }

        // Create NSImage for Quick Access / annotation preview
        let previewImage = NSImage(
            cgImage: cgImage,
            size: NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        )

        return (previewImage, url)
    }

    // MARK: - UI Updates

    private func refreshToolbar() {
        toolbarPanel?.show(
            below: captureRect,
            state: state,
            frameCount: frames.count,
            showHeightWarning: showHeightWarning,
            onStartCapture: { [weak self] in self?.startCapture() },
            onCaptureFrame: { [weak self] in self?.captureFrame() },
            onAutoScroll: { [weak self] in self?.startAutoScroll() },
            onPauseAutoScroll: { [weak self] in self?.pauseAutoScroll() },
            onCancel: { [weak self] in self?.cancel() },
            onDone: { [weak self] in self?.finish() },
            onHelp: { [weak self] in self?.showHelp() }
        )
    }

    private func showHelp() {
        print("📖 showHelp() called from toolbar")

        // Hide all UI panels for a clean screen while showing help
        bracketWindow?.orderOut(nil)
        toolbarPanel?.dismiss()
        previewPanel?.dismiss()

        if helpPanel == nil {
            helpPanel = ScrollCaptureHelpPanel()
        }
        helpPanel?.show(onDismiss: { [weak self] in
            guard let self else { return }
            self.helpPanel?.dismiss()

            // Restore all UI panels with previous state
            self.bracketWindow?.orderFront(nil)
            self.refreshToolbar()
            self.refreshPreview()
        })
    }

    /// Cached full-stitch preview — only regenerated every N frames to avoid O(n^2) work.
    private var cachedPreviewImage: NSImage?
    private var cachedPreviewFrameCount = 0
    /// Re-stitch preview every N frames to balance responsiveness vs performance.
    private let previewStitchInterval = 5

    private func refreshPreview() {
        guard !frames.isEmpty else { return }

        let sf = NSScreen.main?.backingScaleFactor ?? 2.0

        if frames.count == 1 {
            cachedPreviewImage = NSImage(
                cgImage: frames[0],
                size: NSSize(width: Double(frames[0].width) / sf, height: Double(frames[0].height) / sf)
            )
            cachedPreviewFrameCount = 1
        } else if frames.count - cachedPreviewFrameCount >= previewStitchInterval
                    || cachedPreviewImage == nil {
            // Full re-stitch periodically (every 5 frames) instead of every frame.
            // This reduces O(n^2) memory/CPU from stitching all frames every 350ms.
            cachedPreviewImage = engine.stitchFrames(frames, overlaps: overlaps)
            cachedPreviewFrameCount = frames.count
        }

        previewPanel?.update(image: cachedPreviewImage, frameCount: frames.count)
    }
}
