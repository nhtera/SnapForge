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

    // MARK: - Start Capture Session

    func startCapture(mode: CaptureMode) {
        currentMode = mode

        switch mode {
        case .fullscreen:
            captureFullscreen()
        case .window:
            showOverlay(mode: .window)
        case .area:
            showOverlay(mode: .area)
        case .timedArea:
            startTimedCapture()
        }
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

    private func handleWindowClicked(at screenPoint: CGPoint) {
        dismissOverlay()

        Task {
            do {
                try await scKitService.refreshContent()

                // Find the window under the click point
                let matchingWindow = scKitService.availableWindows.first { window in
                    window.frame.contains(screenPoint)
                }

                guard let target = matchingWindow else {
                    print("⚠️ No window found at click point")
                    return
                }

                let image = try await scKitService.captureWindow(target.scWindow)
                handleCapturedImage(image)
            } catch {
                print("❌ Window capture failed: \(error)")
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
