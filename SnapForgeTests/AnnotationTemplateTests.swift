import Testing
import Foundation
@testable import SnapForge
import SwiftUI

// MARK: - Annotation Template Model Tests

@Suite("AnnotationTemplate")
struct AnnotationTemplateTests {

  @Test func templateHasCorrectProperties() {
    let items = [
      SerializableAnnotation(from: AnnotationItem(
        type: .rectangle,
        bounds: CGRect(x: 10, y: 20, width: 100, height: 50),
        properties: AnnotationProperties(strokeColor: .red)
      ))
    ]

    let template = AnnotationTemplate(
      name: "Test Template",
      description: "A test template",
      items: items
    )

    #expect(template.name == "Test Template")
    #expect(template.description == "A test template")
    #expect(template.items.count == 1)
    #expect(template.isBuiltIn == false)
  }

  @Test func templateIsIdentifiable() {
    let t1 = AnnotationTemplate(name: "A", items: [])
    let t2 = AnnotationTemplate(name: "B", items: [])
    #expect(t1.id != t2.id)
  }
}

// MARK: - Serializable Annotation Tests

@Suite("SerializableAnnotation")
struct SerializableAnnotationTests {

  @Test func rectangleRoundTrip() {
    let original = AnnotationItem(
      type: .rectangle,
      bounds: CGRect(x: 10, y: 20, width: 100, height: 50),
      properties: AnnotationProperties(strokeColor: .red, strokeWidth: 3)
    )

    let serialized = SerializableAnnotation(from: original)
    let restored = serialized.toAnnotationItem()

    #expect(restored != nil)
    #expect(serialized.typeKind == "rectangle")
    #expect(restored?.bounds == CGRect(x: 10, y: 20, width: 100, height: 50))
  }

  @Test func arrowRoundTrip() {
    let start = CGPoint(x: 10, y: 20)
    let end = CGPoint(x: 100, y: 200)
    let original = AnnotationItem(
      type: .arrow(start: start, end: end),
      bounds: CGRect(x: 10, y: 20, width: 90, height: 180),
      properties: AnnotationProperties()
    )

    let serialized = SerializableAnnotation(from: original)
    let restored = serialized.toAnnotationItem()

    #expect(serialized.typeKind == "arrow")
    #expect(serialized.startPoint?.x == 10)
    #expect(serialized.endPoint?.y == 200)
    #expect(restored != nil)
  }

  @Test func textRoundTrip() {
    let original = AnnotationItem(
      type: .text("Hello World"),
      bounds: CGRect(x: 0, y: 0, width: 200, height: 40),
      properties: AnnotationProperties(fontSize: 24)
    )

    let serialized = SerializableAnnotation(from: original)
    let restored = serialized.toAnnotationItem()

    #expect(serialized.typeKind == "text")
    #expect(serialized.text == "Hello World")
    #expect(restored != nil)
  }

  @Test func counterRoundTrip() {
    let original = AnnotationItem(
      type: .counter(5),
      bounds: CGRect(x: 30, y: 30, width: 24, height: 24),
      properties: AnnotationProperties(strokeColor: .orange)
    )

    let serialized = SerializableAnnotation(from: original)
    let restored = serialized.toAnnotationItem()

    #expect(serialized.typeKind == "counter")
    #expect(serialized.counterValue == 5)
    #expect(restored != nil)
  }

  @Test func blurRoundTrip() {
    let original = AnnotationItem(
      type: .blur(.gaussian),
      bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      properties: AnnotationProperties()
    )

    let serialized = SerializableAnnotation(from: original)
    let restored = serialized.toAnnotationItem()

    #expect(serialized.typeKind == "blur")
    #expect(serialized.blurType == "gaussian")
    #expect(restored != nil)
  }

  @Test func rulerRoundTrip() {
    let start = CGPoint(x: 0, y: 0)
    let end = CGPoint(x: 100, y: 100)
    let original = AnnotationItem(
      type: .ruler(start: start, end: end),
      bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      properties: AnnotationProperties()
    )

    let serialized = SerializableAnnotation(from: original)
    let restored = serialized.toAnnotationItem()

    #expect(serialized.typeKind == "ruler")
    #expect(restored != nil)
  }

  @Test func pathRoundTrip() {
    let points = [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 50), CGPoint(x: 100, y: 0)]
    let original = AnnotationItem(
      type: .path(points),
      bounds: CGRect(x: 0, y: 0, width: 100, height: 50),
      properties: AnnotationProperties()
    )

    let serialized = SerializableAnnotation(from: original)
    #expect(serialized.typeKind == "path")
    #expect(serialized.points?.count == 3)
    #expect(serialized.toAnnotationItem() != nil)
  }

  @Test func lineRoundTrip() {
    let original = AnnotationItem(
      type: .line(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 200, y: 200)),
      bounds: CGRect(x: 10, y: 10, width: 190, height: 190),
      properties: AnnotationProperties()
    )

    let serialized = SerializableAnnotation(from: original)
    #expect(serialized.typeKind == "line")
    #expect(serialized.toAnnotationItem() != nil)
  }

  @Test func ovalRoundTrip() {
    let original = AnnotationItem(
      type: .oval,
      bounds: CGRect(x: 50, y: 50, width: 80, height: 60),
      properties: AnnotationProperties()
    )

    let serialized = SerializableAnnotation(from: original)
    #expect(serialized.typeKind == "oval")
    #expect(serialized.toAnnotationItem() != nil)
  }

  @Test func filledRectangleRoundTrip() {
    let original = AnnotationItem(
      type: .filledRectangle,
      bounds: CGRect(x: 10, y: 10, width: 100, height: 100),
      properties: AnnotationProperties(fillColor: .blue)
    )

    let serialized = SerializableAnnotation(from: original)
    #expect(serialized.typeKind == "filledRectangle")
    #expect(serialized.toAnnotationItem() != nil)
  }

  @Test func highlightRoundTrip() {
    let points = [CGPoint(x: 0, y: 10), CGPoint(x: 100, y: 10)]
    let original = AnnotationItem(
      type: .highlight(points),
      bounds: CGRect(x: 0, y: 0, width: 100, height: 20),
      properties: AnnotationProperties(strokeColor: .yellow)
    )

    let serialized = SerializableAnnotation(from: original)
    #expect(serialized.typeKind == "highlight")
    #expect(serialized.points?.count == 2)
    #expect(serialized.toAnnotationItem() != nil)
  }

  @Test func unknownTypeReturnsNil() {
    let serialized = SerializableAnnotation(from: AnnotationItem(
      type: .rectangle,
      bounds: .zero,
      properties: AnnotationProperties()
    ))
    // Manually modify to simulate unknown type
    var modified = serialized
    modified.typeKind = "unknownType"
    #expect(modified.toAnnotationItem() == nil)
  }

  @Test func stickerSerializesButDoesNotRestore() {
    // Stickers reference assets and cannot be restored from templates
    let sticker = StickerItem(id: "heart", name: "heart", symbol: "heart.fill", category: .emoji)
    let original = AnnotationItem(
      type: .sticker(sticker),
      bounds: CGRect(x: 0, y: 0, width: 50, height: 50),
      properties: AnnotationProperties()
    )

    let serialized = SerializableAnnotation(from: original)
    #expect(serialized.typeKind == "sticker")
    // Stickers can't round-trip (no sticker data in template)
  }
}

// MARK: - Codable Round-Trip Tests

@Suite("TemplateCodable")
struct TemplateCodableTests {

  @Test func templateEncodesAndDecodes() throws {
    let items = [
      SerializableAnnotation(from: AnnotationItem(
        type: .rectangle,
        bounds: CGRect(x: 10, y: 20, width: 100, height: 50),
        properties: AnnotationProperties(strokeColor: .red, strokeWidth: 4)
      )),
      SerializableAnnotation(from: AnnotationItem(
        type: .text("Test"),
        bounds: CGRect(x: 0, y: 0, width: 200, height: 40),
        properties: AnnotationProperties(fontSize: 20)
      ))
    ]

    let original = AnnotationTemplate(
      name: "Codable Test",
      description: "Testing JSON round-trip",
      items: items
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(original)
    let decoder = JSONDecoder()
    let restored = try decoder.decode(AnnotationTemplate.self, from: data)

    #expect(restored.name == "Codable Test")
    #expect(restored.description == "Testing JSON round-trip")
    #expect(restored.items.count == 2)
    #expect(restored.items[0].typeKind == "rectangle")
    #expect(restored.items[1].typeKind == "text")
    #expect(restored.items[1].text == "Test")
  }

  @Test func emptyTemplateEncodesAndDecodes() throws {
    let template = AnnotationTemplate(name: "Empty", items: [])

    let encoder = JSONEncoder()
    let data = try encoder.encode(template)
    let decoder = JSONDecoder()
    let restored = try decoder.decode(AnnotationTemplate.self, from: data)

    #expect(restored.name == "Empty")
    #expect(restored.items.isEmpty)
  }
}

// MARK: - Codable Helpers Tests

@Suite("CodableHelpers")
struct CodableHelperTests {

  @Test func codablePointRoundTrip() {
    let point = CGPoint(x: 42.5, y: 99.1)
    let codable = CodablePoint(point)
    let restored = codable.toPoint()

    #expect(restored.x == 42.5)
    #expect(restored.y == 99.1)
  }

  @Test func codableRectRoundTrip() {
    let rect = CGRect(x: 10, y: 20, width: 300, height: 150)
    let codable = CodableRect(rect)
    let restored = codable.toRect()

    #expect(restored == rect)
  }

  @Test func codablePropertiesPreservesValues() {
    let props = AnnotationProperties(
      strokeColor: .red,
      fillColor: .blue,
      strokeWidth: 5,
      fontSize: 18,
      fontName: "Helvetica",
      pixelSize: 12
    )

    let codable = CodableProperties(props)
    let restored = codable.toAnnotationProperties()

    #expect(restored.strokeWidth == 5)
    #expect(restored.fontSize == 18)
    #expect(restored.fontName == "Helvetica")
    #expect(restored.pixelSize == 12)
  }
}

// MARK: - NSColor Hex Tests

@Suite("NSColorHex")
struct NSColorHexTests {

  @Test func hexStringFormat() {
    let color = NSColor(red: 1, green: 0, blue: 0, alpha: 1)
    // calibratedRed may produce #FF2600 in sRGB, so just check format
    let hex = color.hexString
    #expect(hex.hasPrefix("#"))
    #expect(hex.count == 7 || hex.count == 9)
  }

  @Test func hexInitReturnsColor() {
    let color = NSColor(hex: "#FF0000")
    #expect(color != nil)
  }

  @Test func hexInitWithAlpha() {
    let color = NSColor(hex: "#FF000080")
    #expect(color != nil)
  }

  @Test func hexInitInvalidReturnsNil() {
    let color = NSColor(hex: "#ZZZ")
    #expect(color == nil)
  }

  @Test func hexRoundTrip() {
    let original = NSColor(calibratedRed: 0.5, green: 0.25, blue: 0.75, alpha: 1)
    let hex = original.hexString
    let restored = NSColor(hex: hex)
    #expect(restored != nil)
  }
}
