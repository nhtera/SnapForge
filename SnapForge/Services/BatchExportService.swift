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

/// Service for exporting multiple captures as a ZIP archive.
@MainActor
final class BatchExportService {
  static let shared = BatchExportService()
  private init() {}

  /// Progress tracking
  var progress: Double = 0
  var currentItem: String = ""
  var isExporting: Bool = false

  /// Export selected captures to a ZIP file.
  /// Returns the URL of the created ZIP file, or nil on failure.
  func exportBatch(
    captures: [HistoryCapture],
    options: BatchExportOptions
  ) async -> URL? {
    guard !captures.isEmpty else { return nil }

    isExporting = true
    progress = 0
    currentItem = ""

    let exportService = ExportService()
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapForge_BatchExport_\(UUID().uuidString)")

    do {
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

      // Process each capture
      for (index, capture) in captures.enumerated() {
        currentItem = capture.displayName
        progress = Double(index) / Double(captures.count)

        guard let image = NSImage(contentsOfFile: capture.filePath) else { continue }

        let processedImage: NSImage
        if options.resizeEnabled {
          processedImage = resizeImage(image, options: options)
        } else {
          processedImage = image
        }

        let baseName = (capture.filename as NSString).deletingPathExtension
        let filename = "\(baseName).\(options.format.fileExtension)"
        let fileURL = tempDir.appendingPathComponent(filename)

        try exportService.exportImage(
          processedImage,
          format: options.format,
          quality: options.quality,
          to: fileURL
        )

        // Yield to keep UI responsive
        await Task.yield()
      }

      progress = 0.95
      currentItem = "Creating ZIP…"

      // Create ZIP using NSFileCoordinator (sandbox-safe)
      let zipURL = try await createZip(from: tempDir)

      // Clean up temp directory
      try? FileManager.default.removeItem(at: tempDir)

      progress = 1.0
      currentItem = "Done"
      isExporting = false

      return zipURL

    } catch {
      print("❌ Batch export failed: \(error)")
      try? FileManager.default.removeItem(at: tempDir)
      isExporting = false
      return nil
    }
  }

  /// Create ZIP from a directory using NSFileCoordinator (sandbox-safe).
  private func createZip(from sourceDir: URL) async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      let coordinator = NSFileCoordinator()
      var error: NSError?

      // .forUploading on a directory automatically creates a temporary ZIP
      coordinator.coordinate(
        readingItemAt: sourceDir,
        options: .forUploading,
        error: &error
      ) { zipTempURL in
        let destURL = FileManager.default.temporaryDirectory
          .appendingPathComponent("SnapForge_Export_\(UUID().uuidString).zip")
        do {
          try? FileManager.default.removeItem(at: destURL)
          try FileManager.default.copyItem(at: zipTempURL, to: destURL)
          print("✅ Batch export ZIP created: \(destURL.path)")
          continuation.resume(returning: destURL)
        } catch {
          continuation.resume(throwing: error)
        }
      }

      if let error {
        continuation.resume(throwing: error)
      }
    }
  }

  /// Show save panel and move ZIP to user-chosen location.
  func saveWithPanel(zipURL: URL) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "SnapForge_Export.zip"
    panel.allowedContentTypes = [.zip]
    panel.begin { response in
      guard response == .OK, let saveURL = panel.url else { return }
      do {
        try? FileManager.default.removeItem(at: saveURL)
        try FileManager.default.moveItem(at: zipURL, to: saveURL)
        NSWorkspace.shared.activateFileViewerSelecting([saveURL])
        print("✅ Batch export saved to: \(saveURL.path)")
      } catch {
        print("❌ Failed to save ZIP: \(error)")
      }
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
    let resized = NSImage(size: newSize)
    resized.lockFocus()
    image.draw(
      in: NSRect(origin: .zero, size: newSize),
      from: NSRect(origin: .zero, size: originalSize),
      operation: .sourceOver,
      fraction: 1.0
    )
    resized.unlockFocus()
    return resized
  }
}
