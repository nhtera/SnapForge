import AppKit
import QuartzCore

// MARK: - Ripple View (Configurable)

/// Filled circle with stroke border + center dot that expands and fades.
final class ClickRippleView: NSView {
    private let container = CALayer()
    private let config: ClickHighlightConfiguration

    init(center: NSPoint, config: ClickHighlightConfiguration) {
        self.config = config
        let size = config.highlightSize
        let frame = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        super.init(frame: frame)
        wantsLayer = true

        container.frame = bounds
        container.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        container.position = CGPoint(x: bounds.midX, y: bounds.midY)

        let color = config.highlightColor
        let opacity = CGFloat(config.highlightOpacity)

        // Outer filled circle with stroke
        let circleLayer = CAShapeLayer()
        let circleRect = bounds.insetBy(dx: 4, dy: 4)
        circleLayer.path = CGPath(ellipseIn: circleRect, transform: nil)
        circleLayer.fillColor = color.withAlphaComponent(0.2 * opacity).cgColor
        circleLayer.strokeColor = color.withAlphaComponent(0.7 * opacity).cgColor
        circleLayer.lineWidth = 2.5
        container.addSublayer(circleLayer)

        // Center dot
        let dotSize: CGFloat = max(8, size * 0.22)
        let dotRect = CGRect(x: bounds.midX - dotSize / 2, y: bounds.midY - dotSize / 2,
                             width: dotSize, height: dotSize)
        let dotLayer = CAShapeLayer()
        dotLayer.path = CGPath(ellipseIn: dotRect, transform: nil)
        dotLayer.fillColor = color.withAlphaComponent(0.85 * opacity).cgColor
        container.addSublayer(dotLayer)

        layer?.addSublayer(container)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func animateExpandAndFade(completion: @escaping () -> Void) {
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)

        let expandDuration = config.animationDuration * 0.6
        let totalDuration = config.animationDuration

        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 0.3
        scaleAnim.toValue = 1.0
        scaleAnim.duration = expandDuration
        scaleAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        scaleAnim.fillMode = .forwards
        scaleAnim.isRemovedOnCompletion = false
        container.add(scaleAnim, forKey: "expand")

        let opacityAnim = CAKeyframeAnimation(keyPath: "opacity")
        opacityAnim.values = [1.0, 1.0, 0.0]
        opacityAnim.keyTimes = [0, 0.5, 1.0]
        opacityAnim.duration = totalDuration
        opacityAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        opacityAnim.fillMode = .forwards
        opacityAnim.isRemovedOnCompletion = false
        container.add(opacityAnim, forKey: "fade")

        CATransaction.commit()
    }
}

// MARK: - Hold Circle View (Configurable)

/// Persistent filled circle that follows cursor while mouse is held down.
final class ClickHoldCircleView: NSView {
    private let container = CALayer()
    private let diameter: CGFloat

    init(center: NSPoint, config: ClickHighlightConfiguration) {
        self.diameter = config.holdCircleSize
        let frame = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                           width: diameter, height: diameter)
        super.init(frame: frame)
        wantsLayer = true

        container.frame = bounds
        container.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        container.position = CGPoint(x: bounds.midX, y: bounds.midY)
        container.opacity = 0

        let color = config.highlightColor
        let opacity = CGFloat(config.highlightOpacity)

        let circleLayer = CAShapeLayer()
        let circleRect = bounds.insetBy(dx: 2, dy: 2)
        circleLayer.path = CGPath(ellipseIn: circleRect, transform: nil)
        circleLayer.fillColor = color.withAlphaComponent(0.15 * opacity).cgColor
        circleLayer.strokeColor = color.withAlphaComponent(0.5 * opacity).cgColor
        circleLayer.lineWidth = 2
        container.addSublayer(circleLayer)

        layer?.addSublayer(container)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func updateCenter(_ point: NSPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame = CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2,
                       width: diameter, height: diameter)
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
