import AppKit

/// Arrow direction for annotation toolbar popover
enum AnnotationPopoverArrowEdge {
    case top    // Arrow points up (popover below anchor)
    case bottom // Arrow points down (popover above anchor)
}

/// Custom NSView that draws a triangle arrow for the annotation toolbar popover.
/// Arrow center X tracks the annotate button position for precise alignment.
@MainActor
final class RecordingAnnotationPopoverArrowView: NSView {
    var arrowEdge: AnnotationPopoverArrowEdge = .top { didSet { needsDisplay = true } }
    var arrowCenterX: CGFloat = 0 { didSet { needsDisplay = true } }

    private let arrowWidth: CGFloat = 16
    static let arrowHeight: CGFloat = 8

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let clampedCenter = max(arrowWidth / 2 + 4, min(arrowCenterX, bounds.width - arrowWidth / 2 - 4))
        let arrowLeft = clampedCenter - arrowWidth / 2
        let arrowRight = clampedCenter + arrowWidth / 2

        let path = CGMutablePath()
        switch arrowEdge {
        case .top:
            // Arrow at top, pointing up
            path.move(to: CGPoint(x: arrowLeft, y: bounds.maxY - Self.arrowHeight))
            path.addLine(to: CGPoint(x: clampedCenter, y: bounds.maxY))
            path.addLine(to: CGPoint(x: arrowRight, y: bounds.maxY - Self.arrowHeight))
            path.closeSubpath()
        case .bottom:
            // Arrow at bottom, pointing down
            path.move(to: CGPoint(x: arrowLeft, y: Self.arrowHeight))
            path.addLine(to: CGPoint(x: clampedCenter, y: 0))
            path.addLine(to: CGPoint(x: arrowRight, y: Self.arrowHeight))
            path.closeSubpath()
        }

        // Fill arrow with HUD-like dark color to match NSVisualEffectView
        ctx.setFillColor(NSColor(white: 0.15, alpha: 0.9).cgColor)
        ctx.addPath(path)
        ctx.fillPath()
    }
}
