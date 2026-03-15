import AppKit
import Foundation
import UniformTypeIdentifiers

/// Handles exporting captured images to various formats.
@MainActor
final class ExportService {

  enum ExportError: Error, LocalizedError {
    case noImageData
    case writeFailed(String)
    case unsupportedFormat(String)

    var errorDescription: String? {
      switch self {
      case .noImageData: return "No image data available"
      case .writeFailed(let path): return "Failed to write to: \(path)"
      case .unsupportedFormat(let fmt): return "Unsupported format: \(fmt)"
      }
    }
  }

  // MARK: - Export Image

  func exportImage(_ image: NSImage, format: ImageExportFormat, quality: CGFloat = 0.9, to url: URL) throws {
    guard let tiffData = image.tiffRepresentation,
          let bitmapRep = NSBitmapImageRep(data: tiffData)
    else {
      throw ExportError.noImageData
    }

    let data: Data?

    switch format {
    case .png:
      data = bitmapRep.representation(using: .png, properties: [:])
    case .jpg:
      data = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    case .heic:
      data = bitmapRep.heicData(compressionQuality: quality)
    case .webp:
      data = exportAsWebP(bitmapRep: bitmapRep, quality: quality)
    }

    guard let imageData = data else {
      throw ExportError.noImageData
    }

    do {
      try imageData.write(to: url)
    } catch {
      throw ExportError.writeFailed(url.path)
    }
  }

  // MARK: - WebP Export

  private func exportAsWebP(bitmapRep: NSBitmapImageRep, quality: CGFloat) -> Data? {
    guard let cgImage = bitmapRep.cgImage else { return nil }

    let data = NSMutableData()

    // Try multiple WebP UTI identifiers for compatibility
    let webpIdentifiers = ["org.webmproject.webp", "public.webp"]
    var destination: CGImageDestination?

    for identifier in webpIdentifiers {
      destination = CGImageDestinationCreateWithData(
        data as CFMutableData,
        identifier as CFString,
        1,
        nil
      )
      if destination != nil {
        print("✅ WebP: Using identifier '\(identifier)'")
        break
      }
    }

    guard let dest = destination else {
      print("⚠️ WebP encoding not supported on this system — falling back to PNG")
      // Fallback: return PNG data instead
      return bitmapRep.representation(using: .png, properties: [:])
    }

    let options: [CFString: Any] = [
      kCGImageDestinationLossyCompressionQuality: quality
    ]

    CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)

    guard CGImageDestinationFinalize(dest) else {
      print("⚠️ WebP finalize failed — falling back to PNG")
      return bitmapRep.representation(using: .png, properties: [:])
    }

    return data as Data
  }

  // MARK: - Render Annotations onto Image

  /// Render annotations onto base image using AnnotationRenderer (same renderer as canvas)
  func renderAnnotatedImage(
    baseImage: NSImage,
    annotations: [AnnotationItem],
    imageSize: CGSize? = nil
  ) -> NSImage? {
    let size = imageSize ?? baseImage.size
    let result = NSImage(size: size)
    result.lockFocus()

    // Draw the base image
    baseImage.draw(in: NSRect(origin: .zero, size: size))

    guard let context = NSGraphicsContext.current?.cgContext else {
      result.unlockFocus()
      return nil
    }

    // Use the same renderer as the canvas for consistent output
    let renderer = AnnotationRenderer(
      context: context,
      editingTextId: nil,
      sourceImage: baseImage,
      blurCacheManager: nil
    )

    for annotation in annotations {
      renderer.draw(annotation)
    }

    result.unlockFocus()
    return result
  }

  // MARK: - Filename

  func generateFilename(prefix: String = "SnapForge", format: ImageExportFormat) -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    let timestamp = dateFormatter.string(from: Date())
    return "\(prefix)_\(timestamp).\(format.fileExtension)"
  }
}

// MARK: - NSBitmapImageRep HEIC Extension

extension NSBitmapImageRep {
  func heicData(compressionQuality: CGFloat = 0.9) -> Data? {
    guard let cgImage = self.cgImage else { return nil }

    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
      data as CFMutableData,
      "public.heic" as CFString,
      1,
      nil
    ) else { return nil }

    let options: [CFString: Any] = [
      kCGImageDestinationLossyCompressionQuality: compressionQuality
    ]

    CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }

    return data as Data
  }
}
