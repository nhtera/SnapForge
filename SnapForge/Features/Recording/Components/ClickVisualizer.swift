import AppKit
import SwiftUI

/// Displays expanding ripple effects at mouse click locations during screen recording.
final class ClickVisualizer: ObservableObject {
    private var clickMonitor: Any?
    private var rippleWindows: [NSWindow] = []

    @Published var isActive = false
    @Published var rippleColor: NSColor = .systemYellow
    @Published var rippleSize: CGFloat = 40
    @Published var fadeDuration: TimeInterval = 0.4

    // MARK: - Start/Stop

    func start() {
        guard clickMonitor == nil else { return }

        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            self?.showRipple(at: event.locationInWindow, isRightClick: event.type == .rightMouseDown)
        }
        isActive = true
        print("🖱️ Click visualizer started")
    }

    func stop() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        // Clean up any remaining ripple windows
        rippleWindows.forEach { $0.orderOut(nil) }
        rippleWindows.removeAll()
        isActive = false
        print("🖱️ Click visualizer stopped")
    }

    func toggle() {
        isActive ? stop() : start()
    }

    // MARK: - Ripple Effect

    private func showRipple(at screenPoint: CGPoint, isRightClick: Bool) {
        let size = rippleSize * 2  // Start small, expand to this
        let color = isRightClick ? NSColor.systemBlue : rippleColor

        // Convert screen coordinates — NSEvent gives bottom-left origin
        let origin = NSPoint(
            x: screenPoint.x - size / 2,
            y: screenPoint.y - size / 2
        )

        let rippleFrame = NSRect(origin: origin, size: NSSize(width: size, height: size))

        let window = NSWindow(
            contentRect: rippleFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let rippleView = RippleView(
            frame: NSRect(origin: .zero, size: NSSize(width: size, height: size)),
            color: color
        )
        window.contentView = rippleView
        window.makeKeyAndOrderFront(nil)

        rippleWindows.append(window)

        // Animate expand + fade
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = fadeDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            window.orderOut(nil)
            self?.rippleWindows.removeAll { $0 === window }
        })
    }
}

// MARK: - Ripple NSView

private class RippleView: NSView {
    let color: NSColor

    init(frame: NSRect, color: NSColor) {
        self.color = color
        super.init(frame: frame)
        wantsLayer = true

        // Draw concentric circles
        let circleLayer = CAShapeLayer()
        let inset: CGFloat = 4
        let circleRect = bounds.insetBy(dx: inset, dy: inset)
        circleLayer.path = CGPath(ellipseIn: circleRect, transform: nil)
        circleLayer.fillColor = color.withAlphaComponent(0.25).cgColor
        circleLayer.strokeColor = color.withAlphaComponent(0.8).cgColor
        circleLayer.lineWidth = 3
        layer?.addSublayer(circleLayer)

        // Inner dot
        let dotSize: CGFloat = 12
        let dotRect = CGRect(
            x: bounds.midX - dotSize / 2,
            y: bounds.midY - dotSize / 2,
            width: dotSize,
            height: dotSize
        )
        let dotLayer = CAShapeLayer()
        dotLayer.path = CGPath(ellipseIn: dotRect, transform: nil)
        dotLayer.fillColor = color.withAlphaComponent(0.9).cgColor
        layer?.addSublayer(dotLayer)

        // Scale animation (expand from center)
        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 0.3
        scaleAnim.toValue = 1.0
        scaleAnim.duration = 0.3
        scaleAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer?.add(scaleAnim, forKey: "expand")
    }

    required init?(coder: NSCoder) { fatalError() }
}
