import Foundation
import AppKit

/// Clipboard (pasteboard) integration service.
final class ClipboardService {

    /// Copy image to system clipboard.
    func copyImage(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
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
