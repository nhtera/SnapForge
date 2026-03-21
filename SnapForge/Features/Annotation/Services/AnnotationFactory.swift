import CoreGraphics
import SwiftUI

/// Factory for creating annotation items from drawing input
@MainActor
enum AnnotationFactory {

  /// Minimum drag distance (in image points) to create an annotation.
  /// Prevents accidental dot/zero-size annotations from a simple click.
  private static let minimumDragDistance: CGFloat = 3
  private static let minimumBoundsSize: CGFloat = 3

  static func createAnnotation(
    tool: AnnotationToolType,
    from start: CGPoint,
    to end: CGPoint,
    path: [CGPoint],
    state: AnnotateState
  ) -> AnnotationItem? {

    var properties = AnnotationProperties(
      strokeColor: state.strokeColor,
      fillColor: state.fillColor,
      strokeWidth: state.strokeWidth
    )

    // For filled rectangle, auto-apply stroke color as fill if user hasn't set a fill
    if tool == .filledRectangle && state.fillColor == .clear {
      properties.fillColor = state.strokeColor.opacity(1)
    }

    let bounds = CGRect(
      x: min(start.x, end.x),
      y: min(start.y, end.y),
      width: abs(end.x - start.x),
      height: abs(end.y - start.y)
    )

    // Reject shapes with insufficient size (prevents dot on click)
    switch tool {
    case .rectangle, .filledRectangle, .oval, .blur:
      guard bounds.width >= minimumBoundsSize,
            bounds.height >= minimumBoundsSize else { return nil }
    case .arrow, .line, .ruler:
      let distance = hypot(end.x - start.x, end.y - start.y)
      guard distance >= minimumDragDistance else { return nil }
    default:
      break
    }

    let type: AnnotationType?

    switch tool {
    case .rectangle:
      type = .rectangle

    case .filledRectangle:
      type = .filledRectangle

    case .oval:
      type = .oval

    case .arrow:
      type = .arrow(start: start, end: end)

    case .line:
      type = .line(start: start, end: end)

    case .pencil:
      guard path.count > 1 else { return nil }
      type = .path(path)

    case .highlighter:
      guard path.count > 1 else { return nil }
      type = .highlight(path)

    case .blur:
      type = .blur(state.blurType)

    case .counter:
      type = .counter(state.nextCounterValue())

    case .ruler:
      type = .ruler(start: start, end: end)

    case .selection, .crop, .text, .redact, .spotlight, .laserPointer:
      return nil
    }

    guard let annotationType = type else { return nil }
    return AnnotationItem(type: annotationType, bounds: bounds, properties: properties)
  }
}
