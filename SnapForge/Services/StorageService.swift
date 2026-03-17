import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Manages file storage and save locations.
/// Uses SandboxFileAccessManager for proper security-scoped file access in sandbox.
@MainActor
@Observable
final class StorageService {

    enum StorageError: LocalizedError {
        case imageConversionFailed
        case encodingFailed(String)
        case noExportAccess

        var errorDescription: String? {
            switch self {
            case .imageConversionFailed:
                return "Failed to convert image"
            case .encodingFailed(let format):
                return "Failed to encode image as \(format)"
            case .noExportAccess:
                return "No access to export directory. Please choose a save location in Settings."
            }
        }
    }

    private let fileAccess = SandboxFileAccessManager.shared

    /// Resolved save directory — prefers bookmark URL (real path), falls back to stored path.
    var resolvedSaveURL: URL {
        if let bookmarkURL = fileAccess.resolveBookmarkURL() {
            return bookmarkURL
        }
        // Fallback to stored path (may be container path on first launch)
        let path = UserDefaults.standard.string(forKey: SettingsKey.saveLocation)
            ?? fileAccess.defaultPicturesDirectory.deletingLastPathComponent().path
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    /// The SnapForge subdirectory inside the resolved save location.
    var snapForgeDirectory: URL {
        // If bookmark points directly to a "SnapForge" directory, use it as-is.
        // Otherwise, append "SnapForge" subdirectory.
        let resolved = resolvedSaveURL
        if resolved.lastPathComponent == "SnapForge" {
            return resolved
        }
        return resolved.appendingPathComponent("SnapForge")
    }

    init() {
        ensureDefaultDirectoryExists()
    }

    // MARK: - Directory Management

    func ensureDefaultDirectoryExists() {
        let dir = snapForgeDirectory
        let access = fileAccess.beginAccessingURL(dir)
        defer { access.stop() }

        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Save Image

    func saveImage(_ image: NSImage, filename: String, format: String = "png", quality: Double = 0.9) throws -> URL {
        let dir = snapForgeDirectory
        let access = fileAccess.beginAccessingURL(dir)
        defer { access.stop() }

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(filename)

        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            throw StorageError.imageConversionFailed
        }

        let imageData: Data?
        switch format.lowercased() {
        case "jpg", "jpeg":
            imageData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        case "heic":
            if let cgImage = bitmapRep.cgImage {
                let ciImage = CIImage(cgImage: cgImage)
                let context = CIContext()
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                try context.writeHEIFRepresentation(of: ciImage, to: url, format: .RGBA8, colorSpace: colorSpace, options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality])
                return url
            }
            imageData = bitmapRep.representation(using: .png, properties: [:])
        case "webp":
            if let cgImage = bitmapRep.cgImage {
                guard let dest = CGImageDestinationCreateWithURL(
                    url as CFURL, UTType.webP.identifier as CFString, 1, nil
                ) else { throw StorageError.encodingFailed(format) }
                CGImageDestinationAddImage(dest, cgImage, [
                    kCGImageDestinationLossyCompressionQuality: quality
                ] as CFDictionary)
                guard CGImageDestinationFinalize(dest) else {
                    throw StorageError.encodingFailed(format)
                }
                return url
            }
            imageData = bitmapRep.representation(using: .png, properties: [:])
        default:
            imageData = bitmapRep.representation(using: .png, properties: [:])
        }

        guard let data = imageData else {
            throw StorageError.encodingFailed(format)
        }

        try data.write(to: url)
        return url
    }

    // MARK: - Save CGImage (Direct — No TIFF Intermediary)

    /// Save a CGImage directly to disk using CGImageDestination.
    /// Bypasses NSImage.tiffRepresentation — ideal for large scroll captures.
    func saveCGImage(_ cgImage: CGImage, filename: String, format: String = "png", quality: Double = 0.9) throws -> URL {
        let dir = snapForgeDirectory
        let access = fileAccess.beginAccessingURL(dir)
        defer { access.stop() }

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(filename)

        let utType: CFString
        switch format.lowercased() {
        case "jpg", "jpeg":
            utType = UTType.jpeg.identifier as CFString
        case "heic":
            utType = "public.heic" as CFString
        default:
            utType = UTType.png.identifier as CFString
        }

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, utType, 1, nil) else {
            throw StorageError.encodingFailed(format)
        }

        var options: [CFString: Any] = [:]
        if format.lowercased() != "png" {
            options[kCGImageDestinationLossyCompressionQuality] = quality
        }

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw StorageError.encodingFailed(format)
        }

        return url
    }

    // MARK: - Save Video

    func saveVideo(from sourceURL: URL, filename: String) throws -> URL {
        let dir = snapForgeDirectory
        let access = fileAccess.beginAccessingURL(dir)
        defer { access.stop() }

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destinationURL = dir.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    // MARK: - Auto-name

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f
    }()

    func generateImageFilename(format: String = "png") -> String {
        let timestamp = Self.timestampFormatter.string(from: Date())
        return "SnapForge_\(timestamp).\(format)"
    }

    func generateVideoFilename(format: String = "mp4") -> String {
        let timestamp = Self.timestampFormatter.string(from: Date())
        return "SnapForge_Recording_\(timestamp).\(format)"
    }
}
