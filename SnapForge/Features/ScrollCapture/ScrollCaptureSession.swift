import AppKit
import ScreenCaptureKit

/// Orchestrates the scroll capture lifecycle — coordinates engine, UI panels, and scroll simulation.
@MainActor
final class ScrollCaptureSession {

    // MARK: - Public Interface

    var onComplete: ((NSImage) -> Void)?
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
    private var scrollCaptureTimer: Timer?

    // UI panels
    private var bracketWindow: ScrollCaptureBracketWindow?
    private var toolbarPanel: ScrollCaptureToolbarPanel?
    private var previewPanel: ScrollCapturePreviewPanel?
    private var helpPanel: ScrollCaptureHelpPanel?

    // Scroll configuration
    private let scrollAmount: Int32 = -5  // CGEvent line scroll: negative = scroll DOWN
    private let scrollSettleDelay: UInt64 = 500_000_000  // 500ms settle time
    private let maxFrames = 50

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

        let scrollPoint = CGPoint(x: captureRect.midX, y: captureRect.midY)

        autoScrollTask = Task { [weak self] in
            guard let self else { return }

            var consecutiveIdentical = 0

            while !Task.isCancelled, self.state == .autoScrolling, self.frames.count < self.maxFrames {
                engine.simulateScroll(amount: scrollAmount, at: scrollPoint)

                try? await Task.sleep(nanoseconds: scrollSettleDelay)

                guard !Task.isCancelled, self.state == .autoScrolling else { break }

                do {
                    let newFrame = try await engine.captureFrame(rect: captureRect, excludeWindowIDs: uiWindowIDs)

                    if let lastFrame = frames.last, engine.framesAreIdentical(lastFrame, newFrame, threshold: 0.95) {
                        consecutiveIdentical += 1
                        if consecutiveIdentical >= 2 {
                            print("📍 Scroll capture: end of content (\(frames.count) frames)")
                            self.state = .capturing
                            refreshToolbar()
                            startScrollMonitor()
                            break
                        }
                        continue
                    }

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
                    print("📸 Scroll capture: frame \(frames.count) (overlap: \(overlap)px)")

                } catch {
                    print("❌ Scroll capture: frame failed: \(error)")
                    break
                }
            }

            if self.state == .autoScrolling {
                self.state = .capturing
                refreshToolbar()
                startScrollMonitor()
            }
        }
    }

    private func pauseAutoScroll() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
        state = .capturing
        refreshToolbar()
        startScrollMonitor()
    }

    private func finish() {
        guard !frames.isEmpty else { cancel(); return }

        print("✅ Scroll capture: finishing with \(frames.count) frames, \(overlaps.count) overlaps")

        if frames.count == 1 {
            let sf = NSScreen.main?.backingScaleFactor ?? 2.0
            let image = NSImage(
                cgImage: frames[0],
                size: NSSize(width: Double(frames[0].width) / sf, height: Double(frames[0].height) / sf)
            )
            dismiss()
            onComplete?(image)
            return
        }

        guard let stitched = engine.stitchFrames(frames, overlaps: overlaps) else {
            print("❌ Scroll capture: stitching failed")
            dismiss()
            return
        }

        dismiss()
        onComplete?(stitched)
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
        do {
            let newFrame = try await engine.captureFrame(rect: captureRect, excludeWindowIDs: uiWindowIDs)

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
            print("📸 Scroll capture: frame \(frames.count) captured (overlap: \(overlap)px)")
        } catch {
            print("❌ Scroll capture: capture failed: \(error)")
        }
    }

    // MARK: - UI Updates

    private func refreshToolbar() {
        toolbarPanel?.show(
            below: captureRect,
            state: state,
            frameCount: frames.count,
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

    private func refreshPreview() {
        guard !frames.isEmpty else { return }

        let previewImage: NSImage?
        if frames.count == 1 {
            let sf = NSScreen.main?.backingScaleFactor ?? 2.0
            previewImage = NSImage(
                cgImage: frames[0],
                size: NSSize(width: Double(frames[0].width) / sf, height: Double(frames[0].height) / sf)
            )
        } else {
            previewImage = engine.stitchFrames(frames, overlaps: overlaps)
        }

        previewPanel?.update(image: previewImage, frameCount: frames.count)
    }
}
