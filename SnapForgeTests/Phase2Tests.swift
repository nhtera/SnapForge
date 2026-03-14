import AppKit
import Testing

@testable import SnapForge

// MARK: - Auto-Redact Service Tests

struct AutoRedactServiceTests {

  @Test func classifyEmailAsSensitive() {
    let result = AutoRedactService.classifySensitiveText("user@example.com")
    #expect(result == .email)
  }

  @Test func classifyPhoneAsSensitive() {
    let result = AutoRedactService.classifySensitiveText("+1-555-123-4567")
    #expect(result == .phone)
  }

  @Test func classifyPasswordAsSensitive() {
    let result = AutoRedactService.classifySensitiveText("Q9Gni4K4bfW!")
    #expect(result == .password)
  }

  @Test func classifySSNAsSensitive() {
    let result = AutoRedactService.classifySensitiveText("123-45-6789")
    #expect(result == .ssn)
  }

  @Test func classifyIPAsSensitive() {
    let result = AutoRedactService.classifySensitiveText("192.168.1.100")
    #expect(result == .ipAddress)
  }

  @Test func normalTextIsNotSensitive() {
    #expect(AutoRedactService.classifySensitiveText("Sign up") == nil)
    #expect(AutoRedactService.classifySensitiveText("Full name") == nil)
    #expect(AutoRedactService.classifySensitiveText("OK") == nil)
    #expect(AutoRedactService.classifySensitiveText("Hello World") == nil)
  }

  @Test func shortTextIsNotSensitive() {
    #expect(AutoRedactService.classifySensitiveText("Hi") == nil)
    #expect(AutoRedactService.classifySensitiveText("") == nil)
  }

  @Test func detectSensitiveRegionsReturnsEmptyForBlankImage() async {
    let image = NSImage(size: NSSize(width: 100, height: 100))
    image.lockFocus()
    NSColor.white.setFill()
    NSBezierPath.fill(NSRect(x: 0, y: 0, width: 100, height: 100))
    image.unlockFocus()

    let regions = await AutoRedactService.shared.detectSensitiveRegions(in: image)
    // Blank image should have no sensitive content
    #expect(regions.isEmpty)
  }

  @Test func redactRegionDefaultsToSelected() {
    let region = RedactRegion(bounds: .zero, type: .email)
    #expect(region.isSelected == true)
  }

  @Test func redactTypeHasDisplayProperties() {
    for type in RedactType.allCases {
      #expect(!type.displayName.isEmpty)
      #expect(!type.icon.isEmpty)
    }
  }
}

// MARK: - Sticker Item Tests

struct StickerItemTests {

  @Test func builtInStickersHaveContent() {
    #expect(!StickerItem.builtIn.isEmpty)
    #expect(StickerItem.builtIn.count >= 40)
  }

  @Test func allCategoriesHaveStickers() {
    for category in StickerCategory.allCases {
      let count = StickerItem.builtIn.filter { $0.category == category }.count
      #expect(count > 0, "Category \(category.displayName) has no stickers")
    }
  }

  @Test func stickerIdsAreUnique() {
    let ids = StickerItem.builtIn.map(\.id)
    #expect(Set(ids).count == ids.count, "Duplicate sticker IDs found")
  }

  @Test func stickerCategoriesHaveDisplayProperties() {
    for category in StickerCategory.allCases {
      #expect(!category.displayName.isEmpty)
      #expect(!category.icon.isEmpty)
    }
  }

  @Test func stickerAnnotationTypeWorks() {
    let sticker = StickerItem.builtIn[0]
    let annotation = AnnotationItem(
      type: .sticker(sticker),
      bounds: CGRect(x: 10, y: 10, width: 60, height: 60),
      properties: AnnotationProperties()
    )
    #expect(annotation.type == .sticker(sticker))
    #expect(annotation.type.displayName.contains("Sticker"))
  }
}

// MARK: - Metadata Service Tests

struct MetadataServiceTests {

  @MainActor
  @Test func smartFolderFilterAll() {
    let captures = [
      makeCapture(type: .screenshot, daysAgo: 0),
      makeCapture(type: .recording, daysAgo: 3),
    ]
    let result = MetadataService.shared.filter(captures, by: .all)
    #expect(result.count == 2)
  }

  @MainActor
  @Test func smartFolderFilterScreenshots() {
    let captures = [
      makeCapture(type: .screenshot, daysAgo: 0),
      makeCapture(type: .recording, daysAgo: 0),
      makeCapture(type: .gif, daysAgo: 0),
    ]
    let result = MetadataService.shared.filter(captures, by: .screenshots)
    #expect(result.count == 1)
    #expect(result[0].type == .screenshot)
  }

  @MainActor
  @Test func smartFolderFilterToday() {
    let captures = [
      makeCapture(type: .screenshot, daysAgo: 0),
      makeCapture(type: .screenshot, daysAgo: 5),
    ]
    let result = MetadataService.shared.filter(captures, by: .today)
    #expect(result.count == 1)
  }

  @Test func captureMetadataCodable() throws {
    let meta = CaptureMetadata(
      filePath: "/tmp/test.png",
      tags: ["bug", "review"],
      ocrText: "Hello World",
      date: Date(),
      type: "screenshot"
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(meta)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(CaptureMetadata.self, from: data)

    #expect(decoded.id == meta.id)
    #expect(decoded.tags == meta.tags)
    #expect(decoded.ocrText == meta.ocrText)
  }

  @Test func smartFolderHasDisplayProperties() {
    for folder in SmartFolder.allCases {
      #expect(!folder.displayName.isEmpty)
      #expect(!folder.icon.isEmpty)
    }
  }

  // MARK: - Helpers

  private func makeCapture(
    type: HistoryCapture.CaptureType,
    daysAgo: Int
  ) -> HistoryCapture {
    let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
    let ext = type == .recording ? "mp4" : type == .gif ? "gif" : "png"
    return HistoryCapture(
      filename: "test_\(UUID().uuidString).\(ext)",
      filePath: "/tmp/test_\(UUID().uuidString).\(ext)",
      date: date,
      fileSize: 1024,
      type: type
    )
  }
}
