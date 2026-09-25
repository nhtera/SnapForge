import Foundation
import AppKit
import UniformTypeIdentifiers

/// Clipboard (pasteboard) integration service.
@MainActor
final class ClipboardService {

    /// Timestamp formatter for clipboard filenames
    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f
    }()

    /// Track previous temp file URL so we can clean it up on next copy
    private var previousTempURL: URL?

    /// Copy image to system clipboard with a proper filename.
    /// Writes a single pasteboard item carrying both a file URL to a temp PNG and the
    /// image data (PNG + TIFF). Apps that read image data (terminals like Claude Code,
    /// Slack, Preview) get the pixels; apps that prefer files (Finder, Telegram) get
    /// the file with its filename.
    func copyImage(_ image: NSImage) {
        let tiffData = image.tiffRepresentation
        guard let pngData = Self.pngData(fromTIFF: tiffData) else {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
            return
        }

        // Generate a proper filename
        let timestamp = Self.timestampFormatter.string(from: Date())
        let filename = "SnapForge_\(timestamp).png"
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(filename)

        // Clean up previous temp file to avoid accumulating stale files.
        // Safe: the clipboard is about to be replaced, so nothing references it anymore.
        if let prev = previousTempURL { try? FileManager.default.removeItem(at: prev) }
        previousTempURL = tempURL

        var fileURL: URL?
        do {
            try pngData.write(to: tempURL, options: .atomic)
            fileURL = tempURL
        } catch {
            print("❌ ClipboardService: temp file write failed: \(error)")
        }

        writeImageItem(fileURL: fileURL, representations: [(.png, pngData), (.tiff, tiffData)])
    }

    /// Copy image as PNG data to system clipboard (explicit alias).
    func copyImageAsPNG(_ image: NSImage) {
        copyImage(image)
    }

    /// Copy an image file to the clipboard, preserving the filename.
    /// Also includes the file's original bytes plus PNG/TIFF data so apps that only
    /// accept image data can paste it.
    func copyImageFile(_ url: URL) {
        let image = NSImage(contentsOf: url)
        let tiffData = image?.tiffRepresentation
        var representations: [(NSPasteboard.PasteboardType, Data?)] = []
        if let encodedType = Self.pasteboardImageType(forExtension: url.pathExtension),
           encodedType != .png, encodedType != .tiff {
            representations.append((encodedType, try? Data(contentsOf: url)))
        }
        representations.append((.png, Self.pngData(fromTIFF: tiffData)))
        representations.append((.tiff, tiffData))
        writeImageItem(fileURL: url, representations: representations)
    }

    /// Write one pasteboard item with a file URL (when available) plus image data.
    ///
    /// The file URL goes through `writeObjects([NSURL])` because that is what grants
    /// sandboxed receivers read access to the file — `NSPasteboardItem.setString(_:forType: .fileURL)`
    /// does not. The image representations are then added to that same item with
    /// `addTypes`/`setData`, so receivers see one image rather than two clipboard items.
    private func writeImageItem(
        fileURL: URL?,
        representations: [(NSPasteboard.PasteboardType, Data?)]
    ) {
        let available = representations.compactMap { type, data in data.map { (type, $0) } }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        guard let fileURL else {
            pasteboard.declareTypes(available.map { $0.0 }, owner: nil)
            for (type, data) in available { pasteboard.setData(data, forType: type) }
            return
        }

        pasteboard.writeObjects([fileURL as NSURL])
        guard !available.isEmpty else { return }
        pasteboard.addTypes(available.map { $0.0 }, owner: nil)
        for (type, data) in available { pasteboard.setData(data, forType: type) }
    }

    private static func pngData(fromTIFF tiffData: Data?) -> Data? {
        guard let tiffData, let rep = NSBitmapImageRep(data: tiffData) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func pasteboardImageType(forExtension ext: String) -> NSPasteboard.PasteboardType? {
        guard let type = UTType(filenameExtension: ext.lowercased()), type.conforms(to: .image) else {
            return nil
        }
        return NSPasteboard.PasteboardType(type.identifier)
    }

    /// Copy text to system clipboard.
    func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Copy file URL to system clipboard (for drag-drop).
    func copyFileURL(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }

    /// Get image from clipboard.
    func getImageFromClipboard() -> NSImage? {
        let pasteboard = NSPasteboard.general
        guard let items = pasteboard.readObjects(forClasses: [NSImage.self], options: nil),
              let image = items.first as? NSImage else {
            return nil
        }
        return image
    }
}

