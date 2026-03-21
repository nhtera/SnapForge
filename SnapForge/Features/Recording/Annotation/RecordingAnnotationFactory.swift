import CoreGraphics
import SwiftUI

/// Converts mouse gestures into AnnotationItems for recording annotations
enum RecordingAnnotationFactory {

    /// Create an annotation from drawing gesture data. Returns nil for selection tool.
    static func createAnnotation(
        tool: AnnotationToolType,
        from start: CGPoint,
        to end: CGPoint,
        path: [CGPoint],
        strokeColor: Color,
        strokeWidth: CGFloat
    ) -> AnnotationItem? {
        let props = AnnotationProperties(
            strokeColor: strokeColor,
            strokeWidth: strokeWidth
        )

        switch tool {
        case .rectangle:
            let bounds = makeRect(from: start, to: end)
            return AnnotationItem(type: .rectangle, bounds: bounds, properties: props)

        case .oval:
            let bounds = makeRect(from: start, to: end)
            return AnnotationItem(type: .oval, bounds: bounds, properties: props)

        case .arrow:
            let bounds = makeRect(from: start, to: end)
            return AnnotationItem(type: .arrow(start: start, end: end), bounds: bounds, properties: props)

        case .line:
            let bounds = makeRect(from: start, to: end)
            return AnnotationItem(type: .line(start: start, end: end), bounds: bounds, properties: props)

        case .pencil:
            guard path.count >= 2 else { return nil }
            let bounds = boundingRect(for: path)
            return AnnotationItem(type: .path(path), bounds: bounds, properties: props)

        case .highlighter:
            guard path.count >= 2 else { return nil }
            let bounds = boundingRect(for: path)
            let highlightProps = AnnotationProperties(strokeColor: strokeColor, strokeWidth: strokeWidth * 3)
            return AnnotationItem(type: .highlight(path), bounds: bounds, properties: highlightProps)

        case .blur:
            let bounds = makeRect(from: start, to: end)
            guard bounds.width >= 10, bounds.height >= 10 else { return nil }
            return AnnotationItem(type: .blur(.pixelated), bounds: bounds, properties: props)

        case .spotlight:
            let bounds = makeRect(from: start, to: end)
            guard bounds.width >= 20, bounds.height >= 20 else { return nil }
            return AnnotationItem(type: .spotlight, bounds: bounds, properties: props)

        default:
            return nil
        }
    }

    private static func makeRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x), y: min(start.y, end.y),
            width: abs(end.x - start.x), height: abs(end.y - start.y)
        )
    }

    private static func boundingRect(for points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in points {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
