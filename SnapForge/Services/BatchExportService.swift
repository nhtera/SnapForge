import AppKit
import Foundation

/// Configuration for batch exporting captures.
struct BatchExportOptions {
  var format: ImageExportFormat = .png
  var quality: CGFloat = 0.9
  var resizeEnabled: Bool = false
  var resizeWidth: Int = 1920
  var resizeHeight: Int = 1080
  var maintainAspectRatio: Bool = true
}

/// Service for exporting multiple captures.
@MainActor
final class BatchExportService {
  static let shared = BatchExportService()
  private init() {}

  /// Progress tracking
  var progress: Double = 0
  var currentItem: String = ""
  var isExporting: Bool = false
  var errorMessage: String?

  /// Export selected captures to a folder, then ZIP it.
  /// Returns the URL of the resulting ZIP, or nil on failure.
  func exportBatch(
    captures: [HistoryCapture],
    options: BatchExportOptions
  ) async -> URL? {
    guard !captures.isEmpty else {
      errorMessage = "No captures to export"
      return nil
    }

    isExporting = true
    progress = 0
    currentItem = ""
    errorMessage = nil

    let exportService = ExportService()
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapForge_BatchExport_\(UUID().uuidString)")

    do {
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
      print("✅ Batch export: Created temp dir at \(tempDir.path)")
    } catch {
      print("❌ Batch export: Failed to create temp dir: \(error)")
      errorMessage = "Failed to create temp directory"
      isExporting = false
      return nil
    }

    // Process each capture
    var exportedCount = 0
    for (index, capture) in captures.enumerated() {
      currentItem = capture.displayName
      progress = Double(index) / Double(captures.count)

      guard let image = NSImage(contentsOfFile: capture.filePath) else {
        print("⚠️ Batch export: Skipping \(capture.filename) — could not load image")
        continue
      }

      let processedImage: NSImage
      if options.resizeEnabled {
        processedImage = resizeImage(image, options: options)
      } else {
        processedImage = image
      }

      let baseName = (capture.filename as NSString).deletingPathExtension
      let filename = "\(baseName).\(options.format.fileExtension)"
      let fileURL = tempDir.appendingPathComponent(filename)

      do {
        try exportService.exportImage(
          processedImage,
          format: options.format,
          quality: options.quality,
          to: fileURL
        )
        exportedCount += 1
        print("✅ Batch export: Exported \(filename)")
      } catch {
        print("❌ Batch export: Failed to export \(filename): \(error)")
      }

      // Yield to keep UI responsive
      await Task.yield()
    }

    guard exportedCount > 0 else {
      print("❌ Batch export: No images were exported")
      errorMessage = "Failed to export any images"
      try? FileManager.default.removeItem(at: tempDir)
      isExporting = false
      return nil
    }

    progress = 0.9
    currentItem = "Creating ZIP…"

    // Create ZIP using NSFileCoordinator (sandbox-safe)
    let coordinator = NSFileCoordinator()
    var coordError: NSError?
    var zipResult: URL?

    coordinator.coordinate(
      readingItemAt: tempDir,
      options: .forUploading,
      error: &coordError
    ) { tempZipURL in
      do {
        // Use timestamp for a meaningful name
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let destZipURL = FileManager.default.temporaryDirectory
          .appendingPathComponent("SnapForge_Export_\(timestamp).zip")
        try? FileManager.default.removeItem(at: destZipURL)
        try FileManager.default.copyItem(at: tempZipURL, to: destZipURL)
        zipResult = destZipURL
        print("✅ Batch export: ZIP created at \(destZipURL.path)")
      } catch {
        print("❌ Batch export: Failed to copy ZIP: \(error)")
      }
    }

    // Clean up temp directory
    try? FileManager.default.removeItem(at: tempDir)

    if let coordError {
      print("❌ Batch export: NSFileCoordinator error: \(coordError)")
      errorMessage = "Failed to create ZIP: \(coordError.localizedDescription)"
      isExporting = false
      return nil
    }

    guard let finalURL = zipResult else {
      errorMessage = "Failed to create ZIP archive"
      isExporting = false
      return nil
    }

    progress = 1.0
    currentItem = "Done"
    isExporting = false

    return finalURL
  }

  /// Show save panel and move ZIP to user-chosen location.
  func saveWithPanel(zipURL: URL) {
    // Bring app to front so NSSavePanel is visible
    NSApp.activate()

    let panel = NSSavePanel()
    panel.nameFieldStringValue = zipURL.lastPathComponent
    panel.allowedContentTypes = [.zip]
    panel.canCreateDirectories = true

    let response = panel.runModal()
    guard response == .OK, let saveURL = panel.url else {
      // User cancelled — clean up temp ZIP
      try? FileManager.default.removeItem(at: zipURL)
      return
    }

    do {
      try? FileManager.default.removeItem(at: saveURL)
      try FileManager.default.moveItem(at: zipURL, to: saveURL)
      NSWorkspace.shared.activateFileViewerSelecting([saveURL])
      print("✅ Batch export saved to: \(saveURL.path)")
    } catch {
      print("❌ Failed to save ZIP: \(error)")
    }
  }

  // MARK: - Image Resize

  private func resizeImage(_ image: NSImage, options: BatchExportOptions) -> NSImage {
    let originalSize = image.size
    var targetWidth = CGFloat(options.resizeWidth)
    var targetHeight = CGFloat(options.resizeHeight)

    if options.maintainAspectRatio {
      let widthRatio = targetWidth / originalSize.width
      let heightRatio = targetHeight / originalSize.height
      let scale = min(widthRatio, heightRatio)

      // Don't upscale
      if scale >= 1.0 { return image }

      targetWidth = originalSize.width * scale
      targetHeight = originalSize.height * scale
    }

    let newSize = NSSize(width: targetWidth, height: targetHeight)
    let resized = NSImage(size: newSize, flipped: false) { _ in
      image.draw(
        in: NSRect(origin: .zero, size: newSize),
        from: NSRect(origin: .zero, size: originalSize),
        operation: .sourceOver,
        fraction: 1.0
      )
      return true
    }
    return resized
  }
}
