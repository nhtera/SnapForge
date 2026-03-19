import AppKit
import SwiftUI

/// Displays a floating keystroke overlay during recording.
/// Configurable font size, position, and display duration via KeystrokeOverlayConfiguration.
/// Requires Accessibility permissions (AXIsProcessTrusted).
@MainActor
final class KeystrokeVisualizer {
    static let shared = KeystrokeVisualizer()

    private var monitor: Any?
    private var keystrokeWindow: NSWindow?
    private var dismissTask: Task<Void, Never>?
    private var config = KeystrokeOverlayConfiguration()

    func start() {
        guard AXIsProcessTrusted() else {
            print("⚠️ KeystrokeVisualizer requires Accessibility permission")
            return
        }

        stop()
        config = KeystrokeOverlayConfiguration()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.showKeystroke(event)
            }
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        dismissTask?.cancel()
        keystrokeWindow?.close()
        keystrokeWindow = nil
    }

    private func showKeystroke(_ event: NSEvent) {
        let keyText = formatKeystroke(event)
        guard !keyText.isEmpty else { return }

        dismissTask?.cancel()

        guard let screen = NSScreen.main else { return }

        let keystrokeView = KeystrokeOverlayView(text: keyText, fontSize: config.fontSize)
        let hostingView = NSHostingView(rootView: keystrokeView)
        let size = hostingView.fittingSize

        let windowRect = computeWindowRect(size: size, screen: screen)

        if let window = keystrokeWindow {
            window.contentView = hostingView
            window.setFrame(windowRect, display: true, animate: false)
        } else {
            let window = NSWindow(
                contentRect: windowRect,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.contentView = hostingView
            window.level = .statusBar + 2
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]
            window.makeKeyAndOrderFront(nil)
            keystrokeWindow = window
        }

        keystrokeWindow?.alphaValue = 1.0

        // Auto-dismiss after configured delay
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(config.displayDuration))
            guard !Task.isCancelled else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                self.keystrokeWindow?.animator().alphaValue = 0.0
            }, completionHandler: nil)
        }
    }

    /// Compute window position based on configured position
    private func computeWindowRect(size: CGSize, screen: NSScreen) -> CGRect {
        let frame = screen.visibleFrame
        let edgeOffset: CGFloat = 40
        let width = max(size.width, 60)

        let x: CGFloat
        let y: CGFloat

        switch config.position {
        case .bottomCenter:
            x = frame.midX - width / 2
            y = frame.minY + edgeOffset
        case .bottomLeft:
            x = frame.minX + edgeOffset
            y = frame.minY + edgeOffset
        case .bottomRight:
            x = frame.maxX - width - edgeOffset
            y = frame.minY + edgeOffset
        case .topCenter:
            x = frame.midX - width / 2
            y = frame.maxY - size.height - edgeOffset
        case .topLeft:
            x = frame.minX + edgeOffset
            y = frame.maxY - size.height - edgeOffset
        case .topRight:
            x = frame.maxX - width - edgeOffset
            y = frame.maxY - size.height - edgeOffset
        }

        return CGRect(x: x, y: y, width: width, height: size.height)
    }

    private func formatKeystroke(_ event: NSEvent) -> String {
        var parts: [String] = []

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.control)  { parts.append("⌃") }
        if modifiers.contains(.option)   { parts.append("⌥") }
        if modifiers.contains(.shift)    { parts.append("⇧") }
        if modifiers.contains(.command)  { parts.append("⌘") }

        let specialKeys: [UInt16: String] = [
            36: "⏎", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            115: "Home", 119: "End", 116: "PgUp", 121: "PgDn",
            117: "⌦",
        ]

        if let special = specialKeys[event.keyCode] {
            parts.append(special)
        } else if let chars = event.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty {
            if chars.unicodeScalars.first?.value ?? 0 >= 32 {
                parts.append(chars)
            }
        }

        return parts.isEmpty ? "" : parts.joined()
    }
}

// MARK: - Keystroke Overlay View

struct KeystrokeOverlayView: View {
    let text: String
    var fontSize: CGFloat = 22

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .medium, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(.black.opacity(0.75))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            )
    }
}
