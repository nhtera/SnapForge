import AppKit

/// Ephemeral laser pointer state — tracks cursor trail with fading animation.
/// NOT a persistent annotation — only visible while laser pointer tool is active.
@MainActor @Observable
final class RecordingLaserPointerState {

    struct TrailPoint {
        let position: CGPoint
        let timestamp: Date
    }

    private(set) var trail: [TrailPoint] = []
    var dotSize: CGFloat = 14  // Medium default
    private let maxTrailLength = 30
    private let trailDuration: TimeInterval = 0.5
    private var refreshTimer: Timer?

    /// Weak reference to canvas for triggering redraws
    weak var canvasView: RecordingAnnotationCanvasView?

    // MARK: - Trail Management

    func addPoint(_ point: CGPoint) {
        trail.append(TrailPoint(position: point, timestamp: Date()))
        if trail.count > maxTrailLength {
            trail.removeFirst(trail.count - maxTrailLength)
        }
    }

    // MARK: - Rendering

    /// Draw the fading trail into a CGContext. Called from canvas draw().
    func drawTrail(in ctx: CGContext, color: NSColor) {
        let now = Date()
        // Remove expired points
        trail.removeAll { now.timeIntervalSince($0.timestamp) > trailDuration }
        guard !trail.isEmpty else { return }

        for (index, point) in trail.enumerated() {
            let age = now.timeIntervalSince(point.timestamp)
            let opacity = max(0, 1.0 - age / trailDuration)
            // Shrink as it fades
            let size = dotSize * CGFloat(0.5 + 0.5 * opacity)
            let rect = CGRect(
                x: point.position.x - size / 2,
                y: point.position.y - size / 2,
                width: size, height: size
            )

            ctx.saveGState()
            ctx.setAlpha(opacity * 0.8)
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: rect)

            // Bright white center on the newest (last) point
            if index == trail.count - 1 {
                ctx.setAlpha(1.0)
                let innerSize = size * 0.4
                let innerRect = CGRect(
                    x: point.position.x - innerSize / 2,
                    y: point.position.y - innerSize / 2,
                    width: innerSize, height: innerSize
                )
                ctx.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
                ctx.fillEllipse(in: innerRect)
            }
            ctx.restoreGState()
        }
    }

    // MARK: - Timer Lifecycle

    func startRefreshTimer() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.canvasView?.refresh()
            }
        }
    }

    func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        trail.removeAll()
    }
}
