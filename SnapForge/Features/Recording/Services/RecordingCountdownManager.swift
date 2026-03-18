import SwiftUI
import AppKit

/// Manages the countdown overlay window before recording starts
@MainActor
final class RecordingCountdownManager {
    private var countdownWindow: NSWindow?

    /// Show countdown overlay and await completion
    /// - Parameters:
    ///   - seconds: Countdown duration
    ///   - captureRect: Recording area in CG coordinates (positions badge above selection)
    func showCountdown(seconds: Int, captureRect: CGRect = .zero) async {
        guard let screen = NSScreen.main else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let countdownView = CountdownOverlayView(
                totalSeconds: seconds,
                captureRect: captureRect,
                screenSize: screen.frame.size,
                onComplete: { [weak self] in
                    self?.dismissCountdown()
                    continuation.resume()
                },
                onCancel: { [weak self] in
                    self?.dismissCountdown()
                    continuation.resume()
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
            window.makeKeyAndOrderFront(nil)
            self.countdownWindow = window
        }
    }

    func dismissCountdown() {
        countdownWindow?.close()
        countdownWindow = nil
    }
}
