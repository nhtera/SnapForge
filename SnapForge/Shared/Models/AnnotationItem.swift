import CoreGraphics
import Foundation
import SwiftUI

/// Blur effect type for blur annotations
enum BlurType: String, CaseIterable, Identifiable, Equatable {
  case pixelated
  case gaussian

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .pixelated: return "Pixelated"
    case .gaussian: return "Gaussian"
    }
  }

  var icon: String {
    switch self {
    case .pixelated: return "square.grid.3x3"
    case .gaussian: return "drop.halffull"
    }
  }
}

/// Single annotation element on the canvas
struct AnnotationItem: Identifiable, Equatable {
  let id: UUID
  var type: AnnotationType
  var bounds: CGRect
  var properties: AnnotationProperties

  init(type: AnnotationType, bounds: CGRect, properties: AnnotationProperties) {
    self.id = UUID()
    self.type = type
    self.bounds = bounds
    self.properties = properties
  }
}

/// Types of annotations (value enum with associated data)
enum AnnotationType: Equatable {
  case path([CGPoint])
  case rectangle
  case filledRectangle
  case oval
  case arrow(start: CGPoint, end: CGPoint)
  case line(start: CGPoint, end: CGPoint)
  case text(String)
  case highlight([CGPoint])
  case blur(BlurType)
  case counter(Int)
  case sticker(StickerItem)
  case ruler(start: CGPoint, end: CGPoint)
}

/// Visual properties for an annotation
struct AnnotationProperties: Equatable {
  var strokeColor: Color
  var fillColor: Color
  var strokeWidth: CGFloat
  var fontSize: CGFloat
  var fontName: String
  /// Custom pixel size for blur annotations (0 = use default)
  var pixelSize: CGFloat

  init(
    strokeColor: Color = .red,
    fillColor: Color = .clear,
    strokeWidth: CGFloat = 3,
    fontSize: CGFloat = 16,
    fontName: String = "SF Pro",
    pixelSize: CGFloat = 0
  ) {
    self.strokeColor = strokeColor
    self.fillColor = fillColor
    self.strokeWidth = strokeWidth
    self.fontSize = fontSize
    self.fontName = fontName
    self.pixelSize = pixelSize
  }
}

// MARK: - Hit Testing

extension AnnotationItem {
  /// Check if point hits this annotation with appropriate tolerance
  func containsPoint(_ point: CGPoint, baseTolerance: CGFloat = 6) -> Bool {
    let tolerance = baseTolerance + properties.strokeWidth / 2

    switch type {
    case .rectangle, .filledRectangle, .blur, .sticker:
      return bounds.contains(point)

    case .oval:
      return pointInEllipse(point, in: bounds)

    case .arrow(let start, let end), .line(let start, let end), .ruler(let start, let end):
      return distanceToSegment(point, from: start, to: end) <= tolerance

    case .path(let points), .highlight(let points):
      let adjustedTolerance = type.isHighlight ? tolerance * 3 : tolerance
      return distanceToPolyline(point, points: points) <= adjustedTolerance

    case .text:
      return bounds.contains(point)

    case .counter:
      let center = CGPoint(x: bounds.midX, y: bounds.midY)
      let radius: CGFloat = 12 + baseTolerance
      return hypot(point.x - center.x, point.y - center.y) <= radius
    }
  }

  // MARK: - Geometry Helpers

  private func pointInEllipse(_ point: CGPoint, in rect: CGRect) -> Bool {
    let cx = rect.midX
    let cy = rect.midY
    let rx = rect.width / 2
    let ry = rect.height / 2

    guard rx > 0, ry > 0 else { return false }

    let dx = (point.x - cx) / rx
    let dy = (point.y - cy) / ry
    return (dx * dx + dy * dy) <= 1
  }

  private func distanceToSegment(_ point: CGPoint, from start: CGPoint, to end: CGPoint) -> CGFloat {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let lengthSquared = dx * dx + dy * dy

    guard lengthSquared > 0 else {
      return hypot(point.x - start.x, point.y - start.y)
    }

    // Project point onto line, clamped to segment
    var t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
    t = max(0, min(1, t))

    let projX = start.x + t * dx
    let projY = start.y + t * dy

    return hypot(point.x - projX, point.y - projY)
  }

  private func distanceToPolyline(_ point: CGPoint, points: [CGPoint]) -> CGFloat {
    guard points.count >= 2 else {
      if let first = points.first {
        return hypot(point.x - first.x, point.y - first.y)
      }
      return .infinity
    }

    var minDistance: CGFloat = .infinity
    for i in 0..<(points.count - 1) {
      let dist = distanceToSegment(point, from: points[i], to: points[i + 1])
      minDistance = min(minDistance, dist)
    }
    return minDistance
  }
}

// MARK: - AnnotationType Extension

extension AnnotationType {
  /// Translate embedded point coordinates by (dx, dy).
  /// Used by move, nudge, and crop to shift associated values (arrow endpoints, path points, etc.)
  /// in lockstep with the annotation's bounds.
  func translatingPoints(dx: CGFloat, dy: CGFloat) -> AnnotationType {
    switch self {
    case .arrow(let start, let end):
      return .arrow(
        start: CGPoint(x: start.x + dx, y: start.y + dy),
        end: CGPoint(x: end.x + dx, y: end.y + dy)
      )
    case .line(let start, let end):
      return .line(
        start: CGPoint(x: start.x + dx, y: start.y + dy),
        end: CGPoint(x: end.x + dx, y: end.y + dy)
      )
    case .ruler(let start, let end):
      return .ruler(
        start: CGPoint(x: start.x + dx, y: start.y + dy),
        end: CGPoint(x: end.x + dx, y: end.y + dy)
      )
    case .path(let points):
      return .path(points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) })
    case .highlight(let points):
      return .highlight(points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) })
    default:
      return self
    }
  }

  var isHighlight: Bool {
    if case .highlight = self { return true }
    return false
  }

  /// Human-readable name for the layers panel
  var displayName: String {
    switch self {
    case .path: return "Pencil"
    case .rectangle: return "Rectangle"
    case .filledRectangle: return "Filled Rect"
    case .oval: return "Oval"
    case .arrow: return "Arrow"
    case .line: return "Line"
    case .text(let content):
      let preview = content.prefix(20)
      return preview.isEmpty ? "Text" : "Text: \(preview)"
    case .highlight: return "Highlight"
    case .blur(let blurType): return "Blur (\(blurType.displayName))"
    case .counter(let number): return "Counter #\(number)"
    case .sticker(let item): return "Sticker: \(item.name)"
    case .ruler(let start, let end):
      let dx = end.x - start.x
      let dy = end.y - start.y
      let dist = Int(sqrt(dx * dx + dy * dy))
      return "Ruler (\(dist) px)"
    }
  }

  /// SF Symbol icon name for the layers panel
  var icon: String {
    switch self {
    case .path: return "pencil"
    case .rectangle: return "rectangle"
    case .filledRectangle: return "rectangle.fill"
    case .oval: return "circle"
    case .arrow: return "arrow.up.right"
    case .line: return "line.diagonal"
    case .text: return "character.textbox"
    case .highlight: return "highlighter"
    case .blur: return "eye.slash"
    case .counter: return "list.number"
    case .sticker(let item): return item.symbol
    case .ruler: return "ruler"
    }
  }
}
