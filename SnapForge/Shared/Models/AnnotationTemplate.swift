import CoreGraphics
import Foundation
import SwiftUI

// MARK: - Annotation Template

/// A reusable template that stores annotation layouts for quick application.
struct AnnotationTemplate: Codable, Identifiable {
  let id: UUID
  var name: String
  var description: String
  var items: [SerializableAnnotation]
  var createdAt: Date
  var isBuiltIn: Bool

  init(
    id: UUID = UUID(),
    name: String,
    description: String = "",
    items: [SerializableAnnotation],
    createdAt: Date = Date(),
    isBuiltIn: Bool = false
  ) {
    self.id = id
    self.name = name
    self.description = description
    self.items = items
    self.createdAt = createdAt
    self.isBuiltIn = isBuiltIn
  }
}

// MARK: - Serializable Annotation

/// Codable wrapper for AnnotationItem — flattens associated values for JSON persistence.
struct SerializableAnnotation: Codable {
  var typeKind: String
  var bounds: CodableRect
  var properties: CodableProperties

  // Associated data (optional, depends on typeKind)
  var points: [CodablePoint]?
  var startPoint: CodablePoint?
  var endPoint: CodablePoint?
  var text: String?
  var counterValue: Int?
  var blurType: String?

  init(from item: AnnotationItem) {
    self.bounds = CodableRect(item.bounds)
    self.properties = CodableProperties(item.properties)

    switch item.type {
    case .path(let pts):
      typeKind = "path"
      points = pts.map { CodablePoint($0) }
    case .rectangle:
      typeKind = "rectangle"
    case .filledRectangle:
      typeKind = "filledRectangle"
    case .oval:
      typeKind = "oval"
    case .arrow(let start, let end):
      typeKind = "arrow"
      startPoint = CodablePoint(start)
      endPoint = CodablePoint(end)
    case .line(let start, let end):
      typeKind = "line"
      startPoint = CodablePoint(start)
      endPoint = CodablePoint(end)
    case .text(let content):
      typeKind = "text"
      text = content
    case .highlight(let pts):
      typeKind = "highlight"
      points = pts.map { CodablePoint($0) }
    case .blur(let bt):
      typeKind = "blur"
      blurType = bt.rawValue
    case .counter(let value):
      typeKind = "counter"
      counterValue = value
    case .sticker:
      typeKind = "sticker"
      // Stickers are not serialized in templates (they reference assets)
    case .ruler(let start, let end):
      typeKind = "ruler"
      startPoint = CodablePoint(start)
      endPoint = CodablePoint(end)
    case .spotlight:
      typeKind = "spotlight"
    }
  }

  /// Convert back to AnnotationItem
  func toAnnotationItem() -> AnnotationItem? {
    let annotationType: AnnotationType
    switch typeKind {
    case "path":
      annotationType = .path(points?.map { $0.toPoint() } ?? [])
    case "rectangle":
      annotationType = .rectangle
    case "filledRectangle":
      annotationType = .filledRectangle
    case "oval":
      annotationType = .oval
    case "arrow":
      guard let start = startPoint, let end = endPoint else { return nil }
      annotationType = .arrow(start: start.toPoint(), end: end.toPoint())
    case "line":
      guard let start = startPoint, let end = endPoint else { return nil }
      annotationType = .line(start: start.toPoint(), end: end.toPoint())
    case "text":
      annotationType = .text(text ?? "")
    case "highlight":
      annotationType = .highlight(points?.map { $0.toPoint() } ?? [])
    case "blur":
      let bt = BlurType(rawValue: blurType ?? "pixelated") ?? .pixelated
      annotationType = .blur(bt)
    case "counter":
      annotationType = .counter(counterValue ?? 1)
    case "ruler":
      guard let start = startPoint, let end = endPoint else { return nil }
      annotationType = .ruler(start: start.toPoint(), end: end.toPoint())
    case "spotlight":
      annotationType = .spotlight
    default:
      return nil
    }

    return AnnotationItem(
      type: annotationType,
      bounds: bounds.toRect(),
      properties: properties.toAnnotationProperties()
    )
  }
}

// MARK: - Codable Helpers

struct CodablePoint: Codable {
  var x: CGFloat
  var y: CGFloat

  init(_ point: CGPoint) {
    self.x = point.x
    self.y = point.y
  }

  func toPoint() -> CGPoint {
    CGPoint(x: x, y: y)
  }
}

struct CodableRect: Codable {
  var x: CGFloat
  var y: CGFloat
  var width: CGFloat
  var height: CGFloat

  init(_ rect: CGRect) {
    self.x = rect.origin.x
    self.y = rect.origin.y
    self.width = rect.width
    self.height = rect.height
  }

  func toRect() -> CGRect {
    CGRect(x: x, y: y, width: width, height: height)
  }
}

struct CodableProperties: Codable {
  var strokeColorHex: String
  var fillColorHex: String
  var strokeWidth: CGFloat
  var fontSize: CGFloat
  var fontName: String
  var pixelSize: CGFloat

  init(_ props: AnnotationProperties) {
    self.strokeColorHex = NSColor(props.strokeColor).hexString
    self.fillColorHex = NSColor(props.fillColor).hexString
    self.strokeWidth = props.strokeWidth
    self.fontSize = props.fontSize
    self.fontName = props.fontName
    self.pixelSize = props.pixelSize
  }

  func toAnnotationProperties() -> AnnotationProperties {
    AnnotationProperties(
      strokeColor: Color(nsColor: NSColor(hex: strokeColorHex) ?? .red),
      fillColor: Color(nsColor: NSColor(hex: fillColorHex) ?? .clear),
      strokeWidth: strokeWidth,
      fontSize: fontSize,
      fontName: fontName,
      pixelSize: pixelSize
    )
  }
}

// MARK: - NSColor Hex Extensions

extension NSColor {
  var hexString: String {
    guard let rgb = usingColorSpace(.sRGB) else { return "#FF0000" }
    let r = Int(rgb.redComponent * 255)
    let g = Int(rgb.greenComponent * 255)
    let b = Int(rgb.blueComponent * 255)
    let a = Int(rgb.alphaComponent * 255)
    if a < 255 {
      return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }
    return String(format: "#%02X%02X%02X", r, g, b)
  }

  convenience init?(hex: String) {
    var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

    var rgb: UInt64 = 0
    Scanner(string: hexSanitized).scanHexInt64(&rgb)

    let r, g, b, a: CGFloat
    switch hexSanitized.count {
    case 6:
      r = CGFloat((rgb >> 16) & 0xFF) / 255
      g = CGFloat((rgb >> 8) & 0xFF) / 255
      b = CGFloat(rgb & 0xFF) / 255
      a = 1.0
    case 8:
      r = CGFloat((rgb >> 24) & 0xFF) / 255
      g = CGFloat((rgb >> 16) & 0xFF) / 255
      b = CGFloat((rgb >> 8) & 0xFF) / 255
      a = CGFloat(rgb & 0xFF) / 255
    default:
      return nil
    }

    self.init(calibratedRed: r, green: g, blue: b, alpha: a)
  }
}
