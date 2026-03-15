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

        // Verify the pasteboard has image data
        let pasteboard = NSPasteboard.general
        let types = pasteboard.types ?? []
        #expect(
            types.contains(.tiff) || types.contains(.png),
            "Pasteboard should contain image data after copyImage"
        )
    }
}
