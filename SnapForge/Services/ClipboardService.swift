import Foundation
import AppKit

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
    /// Writes a single pasteboard item carrying both the image data (PNG + TIFF) and a
    /// file URL to a temp PNG. Apps that read image data (terminals like Claude Code,
    /// Slack, Preview) get the pixels; apps that prefer files (Finder, Telegram) get
    /// the file with its filename. macOS grants clipboard recipients sandbox read
    /// access to the referenced file.
    func copyImage(_ image: NSImage) {
        guard let pngData = Self.pngData(from: image) else {
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

        // Clean up previous temp file to avoid accumulating stale files
        if let prev = previousTempURL { try? FileManager.default.removeItem(at: prev) }
        previousTempURL = tempURL

        var fileURL: URL?
        do {
            try pngData.write(to: tempURL, options: .atomic)
            fileURL = tempURL
        } catch {
            print("❌ ClipboardService: temp file write failed: \(error)")
        }

        writeImage(pngData: pngData, tiffData: image.tiffRepresentation, fileURL: fileURL)
    }

    /// Copy image as PNG data to system clipboard (explicit alias).
    func copyImageAsPNG(_ image: NSImage) {
        copyImage(image)
    }

    /// Copy an image file to the clipboard, preserving the filename.
    /// Also includes the image data so apps that only accept image data can paste it.
    func copyImageFile(_ url: URL) {
        guard let image = NSImage(contentsOf: url),
              let pngData = Self.pngData(from: image) else {
            copyFileURL(url)
            return
        }
        writeImage(pngData: pngData, tiffData: image.tiffRepresentation, fileURL: url)
    }

    /// Write one pasteboard item with image data and, when available, a file URL.
    private func writeImage(pngData: Data, tiffData: Data?, fileURL: URL?) {
        let item = NSPasteboardItem()
        item.setData(pngData, forType: .png)
        if let tiffData { item.setData(tiffData, forType: .tiff) }
        if let fileURL { item.setString(fileURL.absoluteString, forType: .fileURL) }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiffData) else { return nil }
        return rep.representation(using: .png, properties: [:])
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

