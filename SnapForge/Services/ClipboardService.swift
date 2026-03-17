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
    /// Saves the PNG to a temp file, then copies the file URL.
    /// macOS grants clipboard recipients sandbox read access to the referenced file,
    /// so receiving apps (Telegram, etc.) preserve the filename.
    func copyImage(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // Generate a proper filename
        let timestamp = Self.timestampFormatter.string(from: Date())
        let filename = "SnapForge_\(timestamp).png"
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(filename)

        // Clean up previous temp file to avoid accumulating stale files
        if let prev = previousTempURL { try? FileManager.default.removeItem(at: prev) }
        previousTempURL = tempURL

        // Write PNG data to temp file
        if let tiffData = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiffData),
           let pngData = rep.representation(using: .png, properties: [:]) {
            do {
                try pngData.write(to: tempURL, options: .atomic)
                // Copy file URL — macOS extends sandbox access for clipboard file URLs
                pasteboard.writeObjects([tempURL as NSURL])
                return
            } catch {
                print("❌ ClipboardService: temp file write failed: \(error)")
            }
        }

        // Fallback: raw PNG data (no filename, but at least the image is copied)
        if let tiffData = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiffData),
           let pngData = rep.representation(using: .png, properties: [:]) {
            pasteboard.setData(pngData, forType: .png)
        } else {
            pasteboard.writeObjects([image])
        }
    }

    /// Copy image as PNG data to system clipboard (explicit alias).
    func copyImageAsPNG(_ image: NSImage) {
        copyImage(image)
    }

    /// Copy an image file to the clipboard, preserving the filename.
    func copyImageFile(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
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

