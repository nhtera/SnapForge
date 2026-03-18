import SwiftUI
import AppKit

/// Manages the countdown overlay window before recording starts
@MainActor
final class RecordingCountdownManager {
    private var countdownWindow: NSWindow?

    /// Show countdown overlay and await completion
    func showCountdown(seconds: Int) async {
        guard let screen = NSScreen.main else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let countdownView = CountdownOverlayView(
                totalSeconds: seconds,
                captureRect: .zero,
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
