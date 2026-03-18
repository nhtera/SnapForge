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
        let location = NSEvent.mouseLocation
        // Skip click effects on toolbar windows (recording/annotation toolbars at .popUpMenu)
        for window in NSApp.windows where window.isVisible && window.level >= .popUpMenu {
            if window.frame.contains(location) { return }
        }
        isMouseDown = true
        overlayWindow?.showClickEffect(at: location)
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

        // Filled ripple effect (original SnapForge style)
        let ripple = ClickRippleView(center: pt)
        contentView.addSubview(ripple)
        ripple.animateExpandAndFade { [weak ripple] in
            ripple?.removeFromSuperview()
        }

        // Persistent hold circle while mouse is held
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

// MARK: - Ripple View (Original SnapForge Style)

/// Filled circle with stroke border + center dot that expands and fades.
private final class ClickRippleView: NSView {
    private let container = CALayer()
    private static let diameter: CGFloat = 44
    private static let color = NSColor.systemYellow

    init(center: NSPoint) {
        let size = Self.diameter
        let frame = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        super.init(frame: frame)
        wantsLayer = true

        // Container with center anchor for proper scale animation
        container.frame = bounds
        container.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        container.position = CGPoint(x: bounds.midX, y: bounds.midY)

        // Outer filled circle with stroke
        let circleLayer = CAShapeLayer()
        let circleRect = bounds.insetBy(dx: 4, dy: 4)
        circleLayer.path = CGPath(ellipseIn: circleRect, transform: nil)
        circleLayer.fillColor = Self.color.withAlphaComponent(0.2).cgColor
        circleLayer.strokeColor = Self.color.withAlphaComponent(0.7).cgColor
        circleLayer.lineWidth = 2.5
        container.addSublayer(circleLayer)

        // Center dot
        let dotSize: CGFloat = 10
        let dotRect = CGRect(x: bounds.midX - dotSize / 2, y: bounds.midY - dotSize / 2,
                             width: dotSize, height: dotSize)
        let dotLayer = CAShapeLayer()
        dotLayer.path = CGPath(ellipseIn: dotRect, transform: nil)
        dotLayer.fillColor = Self.color.withAlphaComponent(0.85).cgColor
        container.addSublayer(dotLayer)

        layer?.addSublayer(container)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func animateExpandAndFade(completion: @escaping () -> Void) {
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)

        // Scale: small → full
        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 0.3
        scaleAnim.toValue = 1.0
        scaleAnim.duration = 0.3
        scaleAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        scaleAnim.fillMode = .forwards
        scaleAnim.isRemovedOnCompletion = false
        container.add(scaleAnim, forKey: "expand")

        // Opacity: appear then fade out
        let opacityAnim = CAKeyframeAnimation(keyPath: "opacity")
        opacityAnim.values = [1.0, 1.0, 0.0]
        opacityAnim.keyTimes = [0, 0.5, 1.0]
        opacityAnim.duration = 0.5
        opacityAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        opacityAnim.fillMode = .forwards
        opacityAnim.isRemovedOnCompletion = false
        container.add(opacityAnim, forKey: "fade")

        CATransaction.commit()
    }
}

// MARK: - Hold Circle View

/// Persistent filled circle that follows cursor while mouse is held down.
private final class ClickHoldCircleView: NSView {
    private let container = CALayer()
    private static let diameter: CGFloat = 30
    private static let color = NSColor.systemYellow

    init(center: NSPoint) {
        let size = Self.diameter
        let frame = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        super.init(frame: frame)
        wantsLayer = true

        container.frame = bounds
        container.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        container.position = CGPoint(x: bounds.midX, y: bounds.midY)
        container.opacity = 0

        // Filled circle with subtle stroke
        let circleLayer = CAShapeLayer()
        let circleRect = bounds.insetBy(dx: 2, dy: 2)
        circleLayer.path = CGPath(ellipseIn: circleRect, transform: nil)
        circleLayer.fillColor = Self.color.withAlphaComponent(0.15).cgColor
        circleLayer.strokeColor = Self.color.withAlphaComponent(0.5).cgColor
        circleLayer.lineWidth = 2
        container.addSublayer(circleLayer)

        layer?.addSublayer(container)
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

        container.add(scaleAnim, forKey: "holdScaleIn")
        container.add(opacityAnim, forKey: "holdFadeIn")
    }

    func animateOut(completion: @escaping () -> Void) {
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1.0; anim.toValue = 0.0
        anim.duration = 0.25
        anim.fillMode = .forwards; anim.isRemovedOnCompletion = false
        container.add(anim, forKey: "holdFadeOut")
        CATransaction.commit()
    }
}
