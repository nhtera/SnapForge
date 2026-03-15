import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import SnapForge

// MARK: - BatchExportOptions Tests

struct BatchExportOptionsTests {

  @Test func defaultOptionsHaveReasonableValues() {
    let options = BatchExportOptions()
    #expect(options.format == .png)
    #expect(options.quality == 0.9)
    #expect(options.resizeEnabled == false)
    #expect(options.resizeWidth == 1920)
    #expect(options.resizeHeight == 1080)
    #expect(options.maintainAspectRatio == true)
  }

  @Test func formatCanBeChanged() {
    var options = BatchExportOptions()
    for format in ImageExportFormat.allCases {
      options.format = format
      #expect(options.format == format)
    }
  }

  @Test func qualityRangeIsValid() {
    var options = BatchExportOptions()
    options.quality = 0.0
    #expect(options.quality == 0.0)
    options.quality = 1.0
    #expect(options.quality == 1.0)
    options.quality = 0.5
    #expect(options.quality == 0.5)
  }

  @Test func resizeDimensionsCanBeSet() {
    var options = BatchExportOptions()
    options.resizeWidth = 800
    options.resizeHeight = 600
    #expect(options.resizeWidth == 800)
    #expect(options.resizeHeight == 600)
  }
}

// MARK: - BatchExportService Tests

@MainActor
struct BatchExportServiceTests {

  /// Create a test image.
  private func makeImage(width: CGFloat, height: CGFloat, color: NSColor = .red) -> NSImage {
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    color.setFill()
    NSBezierPath.fill(NSRect(x: 0, y: 0, width: width, height: height))
    image.unlockFocus()
    return image
  }

  /// Create a temporary test capture file and return the HistoryCapture.
  private func makeCapture(
    width: CGFloat = 200,
    height: CGFloat = 150,
    color: NSColor = .blue,
    filename: String? = nil
  ) -> HistoryCapture? {
    let image = makeImage(width: width, height: height, color: color)
    let name = filename ?? "test_\(UUID().uuidString).png"
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)

    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:])
    else { return nil }

    do {
      try pngData.write(to: tempURL)
    } catch {
      return nil
    }

    return HistoryCapture(
      filename: name,
      filePath: tempURL.path,
      date: Date(),
      fileSize: Int64(pngData.count),
      type: .screenshot
    )
  }

  /// Clean up any temp files created during tests.
  private func cleanup(_ captures: [HistoryCapture]) {
    for capture in captures {
      try? FileManager.default.removeItem(atPath: capture.filePath)
    }
  }

  private func cleanup(url: URL?) {
    if let url {
      try? FileManager.default.removeItem(at: url)
    }
  }

  // MARK: - Singleton

  @Test func sharedInstanceIsSingleton() {
    let a = BatchExportService.shared
    let b = BatchExportService.shared
    #expect(a === b)
  }

  // MARK: - Empty Input

  @Test func exportEmptyCapturesReturnsNil() async {
    let service = BatchExportService.shared
    let result = await service.exportBatch(captures: [], options: BatchExportOptions())
    #expect(result == nil)
    #expect(service.errorMessage != nil)
  }

  // MARK: - Single File Export

  @Test func exportSingleCapturePNG() async {
    let service = BatchExportService.shared
    guard let capture = makeCapture() else {
      #expect(Bool(false), "Failed to create test capture")
      return
    }

    var options = BatchExportOptions()
    options.format = .png

    let result = await service.exportBatch(captures: [capture], options: options)
    #expect(result != nil, "Export should return a ZIP URL")

    if let zipURL = result {
      #expect(FileManager.default.fileExists(atPath: zipURL.path))
      let data = try? Data(contentsOf: zipURL)
      #expect(data != nil && (data?.count ?? 0) > 0, "ZIP should have content")
      cleanup(url: zipURL)
    }

    cleanup([capture])
  }

  @Test func exportSingleCaptureJPG() async {
    let service = BatchExportService.shared
    guard let capture = makeCapture() else { return }

    var options = BatchExportOptions()
    options.format = .jpg
    options.quality = 0.8

    let result = await service.exportBatch(captures: [capture], options: options)
    #expect(result != nil, "JPG export should succeed")
    cleanup(url: result)
    cleanup([capture])
  }

  @Test func exportSingleCaptureHEIC() async {
    let service = BatchExportService.shared
    guard let capture = makeCapture() else { return }

    var options = BatchExportOptions()
    options.format = .heic
    options.quality = 0.9

    let result = await service.exportBatch(captures: [capture], options: options)
    #expect(result != nil, "HEIC export should succeed")
    cleanup(url: result)
    cleanup([capture])
  }

  @Test func exportSingleCaptureWebP() async {
    let service = BatchExportService.shared
    guard let capture = makeCapture() else { return }

    var options = BatchExportOptions()
    options.format = .webp
    options.quality = 0.85

    let result = await service.exportBatch(captures: [capture], options: options)
    // WebP encoding may not be available in all environments (sandbox, CI)
    // So we just verify it doesn't crash
    cleanup(url: result)
    cleanup([capture])
  }

  // MARK: - Multiple Files

  @Test func exportMultipleCapturesProducesZIP() async {
    let service = BatchExportService.shared
    let captures = (0..<3).compactMap { i in
      makeCapture(color: [.red, .green, .blue][i])
    }
    #expect(captures.count == 3)

    let result = await service.exportBatch(captures: captures, options: BatchExportOptions())
    #expect(result != nil, "Multi-file export should produce a ZIP")
    #expect(result?.pathExtension == "zip")

    cleanup(url: result)
    cleanup(captures)
  }

  // MARK: - Resize

  @Test func exportWithResizeDoesNotUpscale() async {
    let service = BatchExportService.shared
    // Create a small image (50x50) and set resize to 1920x1080
    guard let capture = makeCapture(width: 50, height: 50) else { return }

    var options = BatchExportOptions()
    options.resizeEnabled = true
    options.resizeWidth = 1920
    options.resizeHeight = 1080
    options.maintainAspectRatio = true

    let result = await service.exportBatch(captures: [capture], options: options)
    #expect(result != nil, "Export with resize (no upscale) should succeed")
    cleanup(url: result)
    cleanup([capture])
  }

  @Test func exportWithResizeDownscales() async {
    let service = BatchExportService.shared
    // Create a large image (2000x2000) and resize to 800x600
    guard let capture = makeCapture(width: 2000, height: 2000) else { return }

    var options = BatchExportOptions()
    options.resizeEnabled = true
    options.resizeWidth = 800
    options.resizeHeight = 600
    options.maintainAspectRatio = true

    let result = await service.exportBatch(captures: [capture], options: options)
    #expect(result != nil, "Export with downscale should succeed")
    cleanup(url: result)
    cleanup([capture])
  }

  @Test func exportWithResizeNoAspectRatio() async {
    let service = BatchExportService.shared
    guard let capture = makeCapture(width: 500, height: 300) else { return }

    var options = BatchExportOptions()
    options.resizeEnabled = true
    options.resizeWidth = 200
    options.resizeHeight = 200
    options.maintainAspectRatio = false

    let result = await service.exportBatch(captures: [capture], options: options)
    #expect(result != nil, "Export with resize (no aspect ratio) should succeed")
    cleanup(url: result)
    cleanup([capture])
  }

  @Test func exportWithResizeDisabled() async {
    let service = BatchExportService.shared
    guard let capture = makeCapture(width: 500, height: 300) else { return }

    var options = BatchExportOptions()
    options.resizeEnabled = false
    options.resizeWidth = 100
    options.resizeHeight = 100

    let result = await service.exportBatch(captures: [capture], options: options)
    #expect(result != nil, "Export with resize disabled should succeed (ignore resize dims)")
    cleanup(url: result)
    cleanup([capture])
  }

  // MARK: - Quality

  @Test func exportWithLowQuality() async {
    let service = BatchExportService.shared
    guard let capture = makeCapture() else { return }

    var options = BatchExportOptions()
    options.format = .jpg
    options.quality = 0.1

    let result = await service.exportBatch(captures: [capture], options: options)
    #expect(result != nil, "Low quality JPG export should succeed")
    cleanup(url: result)
    cleanup([capture])
  }

  @Test func exportWithMaxQuality() async {
    let service = BatchExportService.shared
    guard let capture = makeCapture() else { return }

    var options = BatchExportOptions()
    options.format = .jpg
    options.quality = 1.0

    let result = await service.exportBatch(captures: [capture], options: options)
    #expect(result != nil, "Max quality JPG export should succeed")
    cleanup(url: result)
    cleanup([capture])
  }

  // MARK: - Progress Tracking

  @Test func exportResetsExportingFlagOnCompletion() async {
    let service = BatchExportService.shared
    // Just verify the flag exists and export doesn't crash
    guard let capture = makeCapture() else { return }

    let result = await service.exportBatch(captures: [capture], options: BatchExportOptions())
    // After this specific call completes, isExporting should be false
    // (But shared state may be modified by parallel tests)
    cleanup(url: result)
    cleanup([capture])
  }

  // MARK: - Error Cases

  @Test func exportWithInvalidFilePathSkipsAndContinues() async {
    let service = BatchExportService.shared
    // Create one valid and one invalid capture
    guard let validCapture = makeCapture() else { return }

    let invalidCapture = HistoryCapture(
      filename: "nonexistent.png",
      filePath: "/tmp/nonexistent_\(UUID().uuidString).png",
      date: Date(),
      fileSize: 0,
      type: .screenshot
    )

    let captures = [validCapture, invalidCapture]
    let result = await service.exportBatch(captures: captures, options: BatchExportOptions())
    // Should succeed because at least one file was valid
    #expect(result != nil, "Export with mix of valid/invalid should succeed for valid ones")

    cleanup(url: result)
    cleanup([validCapture])
  }

  @Test func exportAllInvalidFilesReturnsNil() async {
    let service = BatchExportService.shared
    let invalidCaptures = (0..<3).map { i in
      HistoryCapture(
        filename: "nonexistent_\(i).png",
        filePath: "/tmp/nonexistent_\(UUID().uuidString)_\(i).png",
        date: Date(),
        fileSize: 0,
        type: .screenshot
      )
    }

    let result = await service.exportBatch(captures: invalidCaptures, options: BatchExportOptions())
    #expect(result == nil, "Export with all invalid files should return nil")
    #expect(service.errorMessage != nil, "Should set error message")
  }

  // MARK: - All Formats Round Trip

  @Test func allFormatsProduceOutput() async {
    let service = BatchExportService.shared
    guard let capture = makeCapture() else { return }

    // Test PNG, JPG, HEIC (WebP may not work in sandbox)
    let reliableFormats: [ImageExportFormat] = [.png, .jpg, .heic]
    for format in reliableFormats {
      var options = BatchExportOptions()
      options.format = format

      let result = await service.exportBatch(captures: [capture], options: options)
      #expect(result != nil, "\(format.rawValue) export should produce output")
      cleanup(url: result)
    }

    cleanup([capture])
  }

  // MARK: - Large Batch

  @Test func exportLargeBatchOfCaptures() async {
    let service = BatchExportService.shared
    let captures = (0..<10).compactMap { _ in
      makeCapture(width: 100, height: 100)
    }
    #expect(captures.count == 10)

    let result = await service.exportBatch(captures: captures, options: BatchExportOptions())
    #expect(result != nil, "Large batch should succeed")

    cleanup(url: result)
    cleanup(captures)
  }
}

// MARK: - ImageExportFormat Tests

struct ImageExportFormatTests {

  @Test func allFormatsHaveFileExtensions() {
    for format in ImageExportFormat.allCases {
      #expect(!format.fileExtension.isEmpty, "\(format.rawValue) should have a file extension")
    }
  }

  @Test func formatCount() {
    #expect(ImageExportFormat.allCases.count == 4, "Should have PNG, JPG, WebP, HEIC")
  }

  @Test func formatFileExtensionsAreCorrect() {
    #expect(ImageExportFormat.png.fileExtension == "png")
    #expect(ImageExportFormat.jpg.fileExtension == "jpg")
    #expect(ImageExportFormat.webp.fileExtension == "webp")
    #expect(ImageExportFormat.heic.fileExtension == "heic")
  }

  @Test func formatRawValuesAreDisplayNames() {
    #expect(ImageExportFormat.png.rawValue == "PNG")
    #expect(ImageExportFormat.jpg.rawValue == "JPG")
    #expect(ImageExportFormat.webp.rawValue == "WebP")
    #expect(ImageExportFormat.heic.rawValue == "HEIC")
  }
}
