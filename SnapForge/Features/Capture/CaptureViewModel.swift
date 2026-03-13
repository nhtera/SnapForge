import SwiftUI
import ScreenCaptureKit

/// ViewModel for capture operations — manages selection state and SCK interactions.
@MainActor
@Observable
final class CaptureViewModel {
    var cursorPosition: CGPoint = .zero
    var selectionRect: CGRect?
    var isDragging = false
    var showCrosshair = true
    var showMagnifier = true

    private var dragStartPoint: CGPoint?
    private var captureMode: CaptureMode = .area

    // MARK: - Capture Lifecycle

    func startCapture(mode: CaptureMode) {
        self.captureMode = mode
        showCrosshair = UserDefaults.standard.bool(forKey: "showCrosshair")
        showMagnifier = UserDefaults.standard.bool(forKey: "showMagnifier")

        switch mode {
        case .fullscreen:
            captureFullscreen()
        case .window:
            // Window mode: user clicks a window
            break
        case .area, .timedArea, .ocrCapture:
            // Area mode: user drags to select
            break
        }
    }

    // MARK: - Mouse Events

    func onMouseDown(at point: CGPoint) {
        dragStartPoint = point
        isDragging = true
    }

    func onMouseDragged(to point: CGPoint) {
        guard let start = dragStartPoint else { return }
        let rect = CGRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: abs(point.x - start.x),
            height: abs(point.y - start.y)
        )
        selectionRect = rect
        cursorPosition = point
    }

    func onMouseUp(at point: CGPoint) {
        isDragging = false
        guard let rect = selectionRect, rect.width > 5, rect.height > 5 else {
            selectionRect = nil
            return
        }
        captureArea(rect: rect)
    }

    func onMouseMoved(to point: CGPoint) {
        cursorPosition = point
    }

    func cancel() {
        selectionRect = nil
        isDragging = false
        AppCoordinator.shared.dismissCaptureOverlay()
    }

    // MARK: - Capture Operations

    private func captureFullscreen() {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else { return }

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = display.width * 2 // Retina
                config.height = display.height * 2

                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: config
                )

                let nsImage = NSImage(cgImage: image, size: NSSize(width: display.width, height: display.height))
                    handleCapturedImage(nsImage)
            } catch {
                print("❌ Fullscreen capture failed: \(error)")
            }
        }
    }

    private func captureArea(rect: CGRect) {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else { return }

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()

                // Scale rect to display coordinates
                let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
                config.sourceRect = rect
                config.width = Int(rect.width * scaleFactor)
                config.height = Int(rect.height * scaleFactor)

                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: config
                )

                let nsImage = NSImage(cgImage: image, size: NSSize(width: rect.width, height: rect.height))
                    handleCapturedImage(nsImage)
            } catch {
                print("❌ Area capture failed: \(error)")
            }
        }
    }

    // MARK: - Post-Capture

    private func handleCapturedImage(_ image: NSImage) {
        AppCoordinator.shared.dismissCaptureOverlay()

        // Auto-copy to clipboard
        if UserDefaults.standard.bool(forKey: "autoCopyToClipboard") {
            ClipboardService().copyImage(image)
        }

        // Show Quick Access
        if UserDefaults.standard.bool(forKey: "showQuickAccess") {
            let point = NSEvent.mouseLocation
            AppCoordinator.shared.showQuickAccess(image: image, at: point)
        }
    }
}
