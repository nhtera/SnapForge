import AppKit
import SwiftUI
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
            // Check "Freeze screen during capture" setting
            if UserDefaults.standard.bool(forKey: "freezeScreen") {
                Task { await showFreezeScreen() }
            } else {
                showOverlay(mode: .area)
            }
        case .timedArea:
            startTimedCapture()
        }
    }

    /// Show area selection overlay for recording — callback receives the selected rect
    func startRecordingAreaSelection(completion: @escaping (CGRect) -> Void) {
        recordingAreaCallback = completion

        // Dismiss Quick Access if visible — it steals key window focus
        AppCoordinator.shared.dismissQuickAccess()

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

        if UserDefaults.standard.bool(forKey: "playSounds") {
            NSSound(named: .init("Tink"))?.play()
        }
    }

    // MARK: - Overlay Management

    private func showOverlay(mode: CaptureMode) {
        // Dismiss Quick Access if visible — it can steal key window focus
        AppCoordinator.shared.dismissQuickAccess()

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
        view.showMagnifier = UserDefaults.standard.bool(forKey: "showMagnifier")
        view.showDimensions = UserDefaults.standard.bool(forKey: "showDimensions")

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

        // Force key window after brief delay (ensures it takes focus from any other panels)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(view)
        }

        self.overlayPanel = panel
        self.overlayView = view

        // Play subtle sound (respect setting)
        if UserDefaults.standard.bool(forKey: "playSounds") {
            NSSound(named: .init("Tink"))?.play()
        }
    }

    /// Window capture with clear background + window highlight (CleanShot X style)
    private func showWindowOverlayWithBlur() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame

        let panel = CaptureOverlayPanel(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        let view = CaptureOverlayNSView(frame: screenFrame)
        view.mode = .window

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
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
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

    private var countdownWindow: NSWindow?

    private func startTimedCapture() {
        let delay = UserDefaults.standard.integer(forKey: "timerDelay")
        let seconds = delay > 0 ? delay : 5

        guard let screen = NSScreen.main else { return }

        let countdownView = CountdownOverlayView(
            totalSeconds: seconds,
            onComplete: { [weak self] in
                self?.dismissCountdown()
                // After countdown, show area selection
                self?.showOverlay(mode: .area)
            },
            onCancel: { [weak self] in
                self?.dismissCountdown()
            }
        )

        let hostingView = NSHostingView(rootView: countdownView)

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        // Handle Esc key via local monitor
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                self?.dismissCountdown()
                return nil
            }
            return event
        }

        window.makeKeyAndOrderFront(nil)
        countdownWindow = window

        if UserDefaults.standard.bool(forKey: "playSounds") {
            NSSound(named: .init("Tink"))?.play()
        }
    }

    private func dismissCountdown() {
        countdownWindow?.close()
        countdownWindow = nil
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
        let defaults = UserDefaults.standard
        let env = AppEnvironment.shared

        // Increment capture count
        env.captureCount += 1
        env.lastCapture = image

        // Auto-copy to clipboard
        if defaults.bool(forKey: "autoCopyToClipboard") {
            ClipboardService().copyImage(image)
        }

        // Auto-save (respect the toggle)
        if defaults.bool(forKey: "autoSave") {
            let storage = StorageService()
            let format = defaults.string(forKey: "imageFormat") ?? "png"
            let quality = defaults.double(forKey: "jpegQuality")
            let filename = storage.generateImageFilename(format: format)
            if let saved = try? storage.saveImage(image, filename: filename, format: format, quality: quality) {
                print("✅ Saved capture to: \(saved.path)")
            }
        }

        // Show Quick Access overlay
        if defaults.bool(forKey: "showQuickAccess") {
            let mouseLocation = NSEvent.mouseLocation
            AppCoordinator.shared.showQuickAccess(image: image, at: mouseLocation)
        }

        // Open Annotate tool after capture
        if defaults.bool(forKey: "openAnnotateAfterCapture") {
            AppCoordinator.shared.showAnnotationEditor(for: image)
        }

        // Pin to screen after capture
        if defaults.bool(forKey: "pinAfterCapture") {
            let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
            let pinFrame = NSRect(
                x: screenFrame.midX - 150,
                y: screenFrame.midY - 100,
                width: 300,
                height: 200
            )
            AppCoordinator.shared.pinImage(image, at: pinFrame)
        }

        // Play capture sound (respect the toggle)
        if defaults.bool(forKey: "playSounds") {
            NSSound(named: .init("Glass"))?.play()
        }
    }
}
