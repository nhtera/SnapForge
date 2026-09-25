import Testing
import AppKit
@testable import SnapForge

/// Tests for ClipboardService — copy image to pasteboard
struct ClipboardServiceTests {

    @Test @MainActor func copyImageSetsClipboard() {
        let clipboard = ClipboardService()
        let image = NSImage(size: NSSize(width: 50, height: 50))
        image.lockFocus()
        NSColor.green.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: 50, height: 50))
        image.unlockFocus()

        clipboard.copyImage(image)

        // Image data must be present so apps that only read image data (e.g. Claude Code
        // in a terminal) can paste; the file URL keeps the filename for file-based apps.
        let pasteboard = NSPasteboard.general
        let types = pasteboard.types ?? []
        #expect(types.contains(.png), "Pasteboard should contain PNG data after copyImage")
        #expect(types.contains(.fileURL), "Pasteboard should contain a file URL after copyImage")
        #expect(pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first is NSImage)
    }
}
