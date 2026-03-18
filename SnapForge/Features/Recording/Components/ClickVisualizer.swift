import AppKit
import QuartzCore

// MARK: - Click Visualizer (Service Layer)

/// Detects global mouse clicks and forwards events to the overlay window.
/// Uses NSEvent.mouseLocation for reliable screen-space coordinates.
@MainActor
@Observable
final class ClickVisualizer {
    static let shared = ClickVisualizer()

    private var globalDownMonitor: Any?
    private var localDownMonitor: Any?
    private var globalUpMonitor: Any?
    private var localUpMonitor: Any?
    private var globalDragMonitor: Any?
    private var localDragMonitor: Any?

    private var overlayWindow: ClickHighlightOverlayWindow?
    private var isMouseDown = false
    private(set) var isActive = false

    /// Start click visualization for a given recording area.
    /// The overlay window is included in the recording via SCStream exceptingWindows.
    func start(recordingRect: CGRect = NSScreen.main?.frame ?? .zero) {
        guard !isActive else { return }
        isActive = true

        let window = ClickHighlightOverlayWindow(recordingRect: recordingRect)
        window.orderFrontRegardless()
        overlayWindow = window

        // Mouse-down: show ripple + hold circle
        globalDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMouseDown() }
        }
        localDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleMouseDown() }
            return event
        }

        // Mouse-up: dismiss hold circle
        globalUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMouseUp() }
        }
        localUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleMouseUp() }
            return event
        }

        // Mouse-dragged: move hold circle
        globalDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .rightMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMouseDragged() }
        }
        localDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleMouseDragged() }
            return event
        }
    }

    func stop() {
        let monitors = [globalDownMonitor, localDownMonitor, globalUpMonitor, localUpMonitor, globalDragMonitor, localDragMonitor]
        for m in monitors { if let m { NSEvent.removeMonitor(m) } }
        globalDownMonitor = nil; localDownMonitor = nil
        globalUpMonitor = nil; localUpMonitor = nil
        globalDragMonitor = nil; localDragMonitor = nil
        overlayWindow?.close()
        overlayWindow = nil
        isMouseDown = false
        isActive = false
    }

    /// Window ID for adding to SCStream exceptingWindows (makes effect visible in recording)
    var overlayWindowID: Int? {
        overlayWindow.map { Int($0.windowNumber) }
    }

    private func handleMouseDown() {
        isMouseDown = true
        overlayWindow?.showClickEffect(at: NSEvent.mouseLocation)
    }

    private func handleMouseUp() {
        guard isMouseDown else { return }
        isMouseDown = false
        overlayWindow?.dismissClickEffect()
    }

    private func handleMouseDragged() {
        guard isMouseDown else { return }
        overlayWindow?.moveClickEffect(to: NSEvent.mouseLocation)
    }
}

// MARK: - Overlay Window

/// Single transparent overlay window sized to the recording area.
/// Captured by SCStream via exceptingWindows so click effects appear in recordings.
@MainActor
private final class ClickHighlightOverlayWindow: NSWindow {
    private var holdCircleView: ClickHoldCircleView?

    init(recordingRect: CGRect) {
        super.init(contentRect: recordingRect, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Convert screen point to window-local view coordinates
    private func viewPoint(from screenPoint: NSPoint) -> NSPoint {
        convertPoint(fromScreen: screenPoint)
    }

    func showClickEffect(at screenPoint: NSPoint) {
        guard let contentView else { return }
        let pt = viewPoint(from: screenPoint)

        // Spawn expanding ripple rings (3 staggered rings)
        for i in 0..<3 {
            let delay = CFTimeInterval(i) * 0.1
            let ripple = ClickRippleRingView(center: pt)
            contentView.addSubview(ripple)
            ripple.animateExpand(delay: delay) { [weak ripple] in
                ripple?.removeFromSuperview()
            }
        }

        // Show persistent hold circle
        holdCircleView?.removeFromSuperview()
        let hold = ClickHoldCircleView(center: pt)
        contentView.addSubview(hold)
        hold.animateIn()
        holdCircleView = hold
    }

    func moveClickEffect(to screenPoint: NSPoint) {
        let pt = viewPoint(from: screenPoint)
        holdCircleView?.updateCenter(pt)
    }

    func dismissClickEffect() {
        guard let hold = holdCircleView else { return }
        holdCircleView = nil
        hold.animateOut { [weak hold] in hold?.removeFromSuperview() }
    }
}

// MARK: - Ripple Ring View

/// A single hollow ring that expands outward and fades. Positioned at click point.
private final class ClickRippleRingView: NSView {
    private let ringLayer = CAShapeLayer()
    private static let diameter: CGFloat = 50
    private static let ringWidth: CGFloat = 2
    private static let duration: CFTimeInterval = 0.6
    private static let color = NSColor.systemYellow

    init(center: NSPoint) {
        let size = Self.diameter
        let frame = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false

        let inset = Self.ringWidth / 2
        let path = CGPath(ellipseIn: bounds.insetBy(dx: inset, dy: inset), transform: nil)
        ringLayer.path = path
        ringLayer.fillColor = nil
        ringLayer.strokeColor = Self.color.withAlphaComponent(0.6).cgColor
        ringLayer.lineWidth = Self.ringWidth
        ringLayer.frame = bounds
        ringLayer.opacity = 0
        ringLayer.transform = CATransform3DMakeScale(0.15, 0.15, 1)
        layer?.addSublayer(ringLayer)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func animateExpand(delay: CFTimeInterval, completion: @escaping () -> Void) {
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)

        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 0.15
        scaleAnim.toValue = 1.0
        scaleAnim.duration = Self.duration
        scaleAnim.beginTime = CACurrentMediaTime() + delay
        scaleAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        scaleAnim.fillMode = .both
        scaleAnim.isRemovedOnCompletion = false

        let opacityAnim = CAKeyframeAnimation(keyPath: "opacity")
        opacityAnim.values = [0.0, 0.8, 0.0]
        opacityAnim.keyTimes = [0, 0.25, 1.0]
        opacityAnim.duration = Self.duration
        opacityAnim.beginTime = CACurrentMediaTime() + delay
        opacityAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        opacityAnim.fillMode = .both
        opacityAnim.isRemovedOnCompletion = false

        ringLayer.add(scaleAnim, forKey: "rippleScale")
        ringLayer.add(opacityAnim, forKey: "rippleFade")
        CATransaction.commit()
    }
}

// MARK: - Hold Circle View

/// Persistent hollow circle that follows cursor while mouse is held down.
private final class ClickHoldCircleView: NSView {
    private let ringLayer = CAShapeLayer()
    private static let diameter: CGFloat = 36
    private static let ringWidth: CGFloat = 2
    private static let color = NSColor.systemYellow

    init(center: NSPoint) {
        let size = Self.diameter
        let frame = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false

        let inset = Self.ringWidth / 2
        let path = CGPath(ellipseIn: bounds.insetBy(dx: inset, dy: inset), transform: nil)
        ringLayer.path = path
        ringLayer.fillColor = nil
        ringLayer.strokeColor = Self.color.withAlphaComponent(0.5).cgColor
        ringLayer.lineWidth = Self.ringWidth
        ringLayer.frame = bounds
        ringLayer.opacity = 0
        ringLayer.transform = CATransform3DMakeScale(0.5, 0.5, 1)
        layer?.addSublayer(ringLayer)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func updateCenter(_ point: NSPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame = CGRect(x: point.x - Self.diameter / 2, y: point.y - Self.diameter / 2,
                       width: Self.diameter, height: Self.diameter)
        CATransaction.commit()
    }

    func animateIn() {
        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 0.5; scaleAnim.toValue = 1.0
        scaleAnim.duration = 0.15
        scaleAnim.fillMode = .forwards; scaleAnim.isRemovedOnCompletion = false

        let opacityAnim = CABasicAnimation(keyPath: "opacity")
        opacityAnim.fromValue = 0.0; opacityAnim.toValue = 1.0
        opacityAnim.duration = 0.15
        opacityAnim.fillMode = .forwards; opacityAnim.isRemovedOnCompletion = false

        ringLayer.add(scaleAnim, forKey: "holdScaleIn")
        ringLayer.add(opacityAnim, forKey: "holdFadeIn")
    }

    func animateOut(completion: @escaping () -> Void) {
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1.0; anim.toValue = 0.0
        anim.duration = 0.25
        anim.fillMode = .forwards; anim.isRemovedOnCompletion = false
        ringLayer.add(anim, forKey: "holdFadeOut")
        CATransaction.commit()
    }
}
