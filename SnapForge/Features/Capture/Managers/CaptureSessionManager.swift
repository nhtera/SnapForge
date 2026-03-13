import AppKit
import ScreenCaptureKit

/// Orchestrates the complete capture lifecycle:
/// 1. Show overlay panel → 2. User selects area → 3. Capture via SCK → 4. Post-capture actions
@MainActor
final class CaptureSessionManager {
    static let shared = CaptureSessionManager()

    private var overlayPanel: CaptureOverlayPanel?
    private var overlayView: CaptureOverlayNSView?
    private var freezeWindow: NSWindow?
    private let scKitService = SCKitService()

    private var currentMode: CaptureMode = .area
    private var recordingAreaCallback: ((CGRect) -> Void)?

    // MARK: - Start Capture Session

    func startCapture(mode: CaptureMode) {
        currentMode = mode

        switch mode {
        case .fullscreen:
            captureFullscreen()
        case .window:
            showWindowOverlayWithBlur()
        case .area:
            showOverlay(mode: .area)
        case .timedArea:
            startTimedCapture()
        }
    }

    /// Show area selection overlay for recording — callback receives the selected rect
    func startRecordingAreaSelection(completion: @escaping (CGRect) -> Void) {
        recordingAreaCallback = completion

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame

        let panel = CaptureOverlayPanel(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        let view = CaptureOverlayNSView(frame: screenFrame)
        view.mode = .area
        view.showCrosshair = true
        view.showDimensions = true

        view.onSelectionComplete = { [weak self] rect in
            self?.dismissOverlay()
            self?.recordingAreaCallback?(rect)
            self?.recordingAreaCallback = nil
        }
        view.onCancel = { [weak self] in
            self?.dismissOverlay()
            self?.recordingAreaCallback = nil
        }

        panel.contentView = view
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)

        self.overlayPanel = panel
        self.overlayView = view

        NSSound(named: .init("Tink"))?.play()
    }

    // MARK: - Overlay Management

    private func showOverlay(mode: CaptureMode) {
        // Use the main screen frame
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame

        // Create the overlay panel
        let panel = CaptureOverlayPanel(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Create the view
        let view = CaptureOverlayNSView(frame: screenFrame)
        view.mode = mode
        view.showCrosshair = UserDefaults.standard.bool(forKey: "showCrosshair")
        view.showDimensions = true

        // Wire up callbacks
        view.onSelectionComplete = { [weak self] rect in
            self?.handleAreaSelected(rect)
        }
        view.onWindowClicked = { [weak self] point in
            self?.handleWindowClicked(at: point)
        }
        view.onCancel = { [weak self] in
            self?.dismissOverlay()
        }

        panel.contentView = view
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)

        self.overlayPanel = panel
        self.overlayView = view

        // Play subtle sound
        NSSound(named: .init("Tink"))?.play()
    }

    /// Window capture with frosted/blurred background (CleanShot X style)
    private func showWindowOverlayWithBlur() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame

        Task {
            // 1. Capture freeze-frame of current screen
            var freezeImage: NSImage?
            do {
                freezeImage = try await scKitService.captureFreezeFrame()
            } catch {
                print("⚠️ Freeze frame for window capture failed: \(error)")
            }

            // 2. Blur the freeze-frame for frosted background
            var blurredBG: NSImage?
            if let freeze = freezeImage,
               let cgImage = freeze.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let ciImage = CIImage(cgImage: cgImage)
                let filter = CIFilter(name: "CIGaussianBlur")
                filter?.setValue(ciImage, forKey: kCIInputImageKey)
                filter?.setValue(6.0, forKey: kCIInputRadiusKey)

                if let output = filter?.outputImage {
                    let cropped = output.cropped(to: ciImage.extent)
                    let ctx = CIContext(options: [.cacheIntermediates: false])
                    if let blurredCG = ctx.createCGImage(cropped, from: ciImage.extent) {
                        blurredBG = NSImage(cgImage: blurredCG, size: freeze.size)
                    }
                }
            }

            // 3. Show overlay with blurred background
            let panel = CaptureOverlayPanel(
                contentRect: screenFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )

            let view = CaptureOverlayNSView(frame: screenFrame)
            view.mode = .window
            view.backgroundImage = blurredBG

            view.onWindowClicked = { [weak self] point in
                self?.handleWindowClicked(at: point)
            }
            view.onCancel = { [weak self] in
                self?.dismissOverlay()
            }

            panel.contentView = view
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(view)

            self.overlayPanel = panel
            self.overlayView = view

            NSSound(named: .init("Tink"))?.play()
        }
    }

    func dismissOverlay() {
        overlayPanel?.orderOut(nil)
        overlayPanel = nil
        overlayView = nil
        dismissFreezeWindow()
    }

    // MARK: - Area Capture

    private func handleAreaSelected(_ screenRect: CGRect) {
        // Dismiss overlay first
        dismissOverlay()

        Task {
            do {
                let image = try await scKitService.captureArea(screenRect)
                handleCapturedImage(image)
            } catch {
                print("❌ Area capture failed: \(error)")
            }
        }
    }

    // MARK: - Window Capture

    private func handleWindowClicked(at viewPoint: CGPoint) {
        // Dismiss overlay FIRST so it's not in the window list
        dismissOverlay()

        // Small delay to let the overlay disappear before querying windows
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.captureWindowUnderCursor()
        }
    }

    private func captureWindowUnderCursor() {
        // Get mouse location in CG coordinates (top-left origin)
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.main else { return }
        let screenHeight = screen.frame.height
        let cgMousePoint = CGPoint(x: mouseLocation.x, y: screenHeight - mouseLocation.y)

        // Use CGWindowListCopyWindowInfo to get windows in z-order (front to back)
        guard let windowInfoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            print("⚠️ Failed to get window list")
            return
        }

        let ownBundleID = Bundle.main.bundleIdentifier ?? "com.snapforge.app"
        let excludedOwners: Set<String> = ["Window Server", "Dock", "SystemUIServer"]

        // Find the topmost window at the click point
        var targetWindowID: CGWindowID?
        for info in windowInfoList {
            // Skip our own windows
            if let ownerPID = info[kCGWindowOwnerPID as String] as? Int32 {
                if ownerPID == ProcessInfo.processInfo.processIdentifier { continue }
            }
            if let ownerName = info[kCGWindowOwnerName as String] as? String {
                if excludedOwners.contains(ownerName) { continue }
            }

            // Get window bounds in CG coordinates
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let w = boundsDict["Width"],
                  let h = boundsDict["Height"] else { continue }

            let windowFrame = CGRect(x: x, y: y, width: w, height: h)

            // Skip very small windows (toolbars, hidden windows)
            guard w > 50 && h > 50 else { continue }

            if windowFrame.contains(cgMousePoint) {
                targetWindowID = info[kCGWindowNumber as String] as? CGWindowID
                break // First match = topmost window in z-order
            }
        }

        guard let windowID = targetWindowID else {
            print("⚠️ No window found at cursor position")
            return
        }

        // Now find the matching SCWindow and capture it
        Task {
            do {
                try await scKitService.refreshContent()

                guard let scWindow = scKitService.availableWindows.first(where: { $0.id == windowID }) else {
                    // Fallback: capture using CGWindowListCreateImage
                    print("ℹ️ Window \(windowID) not in SCShareableContent, using CGWindowListCreateImage fallback")
                    captureWindowFallback(windowID: windowID)
                    return
                }

                let image = try await scKitService.captureWindow(scWindow.scWindow)
                handleCapturedImage(image)
            } catch {
                print("❌ Window capture failed: \(error)")
                // Try fallback
                captureWindowFallback(windowID: windowID)
            }
        }
    }

    /// Fallback: Use full SCShareableContent to search all windows by ID
    private func captureWindowFallback(windowID: CGWindowID) {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                    print("❌ Window \(windowID) not found in SCShareableContent")
                    return
                }

                let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                let config = SCStreamConfiguration()
                let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
                config.width = Int(scWindow.frame.width * scaleFactor)
                config.height = Int(scWindow.frame.height * scaleFactor)
                config.showsCursor = false
                config.captureResolution = .best
                config.shouldBeOpaque = false

                let cgImage = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: config
                )

                let nsImage = NSImage(
                    cgImage: cgImage,
                    size: NSSize(width: scWindow.frame.width, height: scWindow.frame.height)
                )
                handleCapturedImage(nsImage)
            } catch {
                print("❌ Window capture fallback failed: \(error)")
            }
        }
    }

    // MARK: - Fullscreen Capture

    private func captureFullscreen() {
        Task {
            do {
                let image = try await scKitService.captureFullscreen()
                handleCapturedImage(image)
            } catch {
                print("❌ Fullscreen capture failed: \(error)")
            }
        }
    }

    // MARK: - Timed Capture

    private func startTimedCapture() {
        let delay = UserDefaults.standard.integer(forKey: "timerDelay")
        let seconds = delay > 0 ? delay : 5

        // TODO: Show countdown overlay
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) { [weak self] in
            self?.showOverlay(mode: .area)
        }
    }

    // MARK: - Freeze Screen

    func showFreezeScreen() async {
        guard let screen = NSScreen.main else { return }

        do {
            let freezeImage = try await scKitService.captureFreezeFrame()

            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = .init(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) - 1)
            window.isOpaque = true
            window.backgroundColor = .black

            let imageView = NSImageView(frame: screen.frame)
            imageView.image = freezeImage
            imageView.imageScaling = .scaleAxesIndependently
            window.contentView = imageView

            window.makeKeyAndOrderFront(nil)
            self.freezeWindow = window

            // Show the selection overlay on top of the freeze
            showOverlay(mode: .area)
        } catch {
            print("❌ Freeze frame failed: \(error)")
            showOverlay(mode: .area)
        }
    }

    private func dismissFreezeWindow() {
        freezeWindow?.orderOut(nil)
        freezeWindow = nil
    }

    // MARK: - Post-Capture

    private func handleCapturedImage(_ image: NSImage) {
        // Increment capture count
        let env = AppEnvironment.shared
        env.captureCount += 1
        env.lastCapture = image

        // Auto-copy to clipboard
        if UserDefaults.standard.bool(forKey: "autoCopyToClipboard") {
            ClipboardService().copyImage(image)
        }

        // Auto-save
        let storage = StorageService()
        let filename = storage.generateImageFilename()
        if let saved = try? storage.saveImage(image, filename: filename) {
            print("✅ Saved capture to: \(saved.path)")
        }

        // Show Quick Access overlay
        if UserDefaults.standard.bool(forKey: "showQuickAccess") {
            let mouseLocation = NSEvent.mouseLocation
            AppCoordinator.shared.showQuickAccess(image: image, at: mouseLocation)
        }

        // Play capture sound
        NSSound(named: .init("Glass"))?.play()
    }
}
