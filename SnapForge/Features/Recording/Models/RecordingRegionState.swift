import AppKit

/// Resize handle positions for region overlay
enum RecordingResizeHandle: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
    case topCenter, bottomCenter, leftCenter, rightCenter

    /// Appropriate resize cursor for this handle
    var cursor: NSCursor {
        switch self {
        case .topLeft, .bottomRight: return .crosshair
        case .topRight, .bottomLeft: return .crosshair
        case .topCenter, .bottomCenter: return .resizeUpDown
        case .leftCenter, .rightCenter: return .resizeLeftRight
        }
    }
}

/// Observable state for the interactive recording region overlay
@MainActor @Observable
final class RecordingRegionState {
    /// Current region rect in Cocoa coordinates (y=0 at bottom)
    var rect: CGRect
    var isDragging: Bool = false
    var isResizing: Bool = false
    var activeHandle: RecordingResizeHandle?

    var onRectChanged: ((CGRect) -> Void)?
    var onDoubleClick: (() -> Void)?
    var onCancel: (() -> Void)?

    static let minimumSize: CGFloat = 100
    static let handleSize: CGFloat = 16  // Hit area for corner brackets and edge dots

    init(rect: CGRect) {
        self.rect = rect
    }

    /// Compute the handle rect at the given position
    func handleRect(for handle: RecordingResizeHandle) -> CGRect {
        let s = Self.handleSize
        let r = rect
        let center: CGPoint
        switch handle {
        case .topLeft:      center = CGPoint(x: r.minX, y: r.maxY)
        case .topRight:     center = CGPoint(x: r.maxX, y: r.maxY)
        case .bottomLeft:   center = CGPoint(x: r.minX, y: r.minY)
        case .bottomRight:  center = CGPoint(x: r.maxX, y: r.minY)
        case .topCenter:    center = CGPoint(x: r.midX, y: r.maxY)
        case .bottomCenter: center = CGPoint(x: r.midX, y: r.minY)
        case .leftCenter:   center = CGPoint(x: r.minX, y: r.midY)
        case .rightCenter:  center = CGPoint(x: r.maxX, y: r.midY)
        }
        return CGRect(x: center.x - s / 2, y: center.y - s / 2, width: s, height: s)
    }
}
