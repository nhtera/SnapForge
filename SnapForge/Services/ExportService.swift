import Foundation
import AppKit
import UniformTypeIdentifiers

/// Handles exporting captured images to various formats.
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
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
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
            // WebP requires CGImageDestination
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
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.webP.identifier as CFString,
            1,
            nil
        ) else { return nil }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { return nil }

        return data as Data
    }

    // MARK: - HEIC Helper

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
