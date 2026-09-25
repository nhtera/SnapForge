import Testing
import AppKit
import UniformTypeIdentifiers
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
        #expect(pasteboard.pasteboardItems?.count == 1, "Image should be a single clipboard item")
        #expect(types.contains(.png), "Pasteboard should contain PNG data after copyImage")
        #expect(types.contains(.tiff), "Pasteboard should contain TIFF data after copyImage")
        #expect(types.contains(.fileURL), "Pasteboard should contain a file URL after copyImage")
        #expect((pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.count == 1)
        #expect(pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first is NSImage)
    }

    @Test @MainActor func copyImageFileIncludesFileURLAndImageData() throws {
        let image = NSImage(size: NSSize(width: 20, height: 20))
        image.lockFocus()
        NSColor.red.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: 20, height: 20))
        image.unlockFocus()

        let rep = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let jpegData = try #require(rep.representation(using: .jpeg, properties: [:]))
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapForgeTest_\(UUID().uuidString).jpg")
        try jpegData.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        ClipboardService().copyImageFile(fileURL)

        let pasteboard = NSPasteboard.general
        let item = try #require(pasteboard.pasteboardItems?.first)
        #expect(pasteboard.pasteboardItems?.count == 1)
        #expect(item.types.contains(.fileURL))
        #expect(item.types.contains(NSPasteboard.PasteboardType(UTType.jpeg.identifier)))
        #expect(item.types.contains(.png))
        #expect(item.types.contains(.tiff))
    }
}
