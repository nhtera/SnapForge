import Foundation
import AppKit

/// Manages file storage, save locations, and Security-Scoped Bookmarks.
@MainActor
@Observable
final class StorageService {

    enum StorageError: LocalizedError {
        case imageConversionFailed
        case encodingFailed(String)

        var errorDescription: String? {
            switch self {
            case .imageConversionFailed:
                return "Failed to convert image"
            case .encodingFailed(let format):
                return "Failed to encode image as \(format)"
            }
        }
    }

    var defaultSaveURL: URL {
        let path = UserDefaults.standard.string(forKey: SettingsKey.saveLocation)
            ?? NSSearchPathForDirectoriesInDomains(.picturesDirectory, .userDomainMask, true).first
            ?? "~/Pictures"
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    init() {
        ensureDefaultDirectoryExists()
    }

    // MARK: - Directory Management

    func ensureDefaultDirectoryExists() {
        let snapForgeDir = defaultSaveURL.appendingPathComponent("SnapForge")
        if !FileManager.default.fileExists(atPath: snapForgeDir.path) {
            try? FileManager.default.createDirectory(at: snapForgeDir, withIntermediateDirectories: true)
        }
    }

    var snapForgeDirectory: URL {
        defaultSaveURL.appendingPathComponent("SnapForge")
    }

    // MARK: - Save Image

    func saveImage(_ image: NSImage, filename: String, format: String = "png", quality: Double = 0.9) throws -> URL {
        let url = snapForgeDirectory.appendingPathComponent(filename)

        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            throw StorageError.imageConversionFailed
        }

        let imageData: Data?
        switch format.lowercased() {
        case "jpg", "jpeg":
            imageData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        case "heic":
            // CIImage route for HEIC — NSBitmapImageRep doesn't directly support HEIC
            if let cgImage = bitmapRep.cgImage {
                let ciImage = CIImage(cgImage: cgImage)
                let context = CIContext()
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                try context.writeHEIFRepresentation(of: ciImage, to: url, format: .RGBA8, colorSpace: colorSpace, options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality])
                return url
            }
            imageData = bitmapRep.representation(using: .png, properties: [:])
        default: // "png", "webp" (webp falls back to png)
            imageData = bitmapRep.representation(using: .png, properties: [:])
        }

        guard let data = imageData else {
            throw StorageError.encodingFailed(format)
        }

        try data.write(to: url)
        return url
    }

    // MARK: - Save Video

    func saveVideo(from sourceURL: URL, filename: String) throws -> URL {
        let destinationURL = snapForgeDirectory.appendingPathComponent(filename)
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

    // MARK: - Security-Scoped Bookmarks

    func saveBookmark(for url: URL) throws {
        let bookmarkData = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmarkData, forKey: SettingsKey.saveLocationBookmark)
    }

    func resolveBookmark() -> URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: SettingsKey.saveLocationBookmark) else { return nil }
        var isStale = false
        let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        if isStale {
            // Re-save bookmark
            if let url = url {
                try? saveBookmark(for: url)
            }
        }
        _ = url?.startAccessingSecurityScopedResource()
        return url
    }
}
