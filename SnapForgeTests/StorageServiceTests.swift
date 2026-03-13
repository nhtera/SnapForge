import Testing
import Foundation
import AppKit
@testable import SnapForge

/// Tests for StorageService — file naming, saving, directory management
@MainActor
struct StorageServiceTests {

    let sut = StorageService()

    // MARK: - Filename Generation

    @Test func generateImageFilenameDefaultFormat() {
        let filename = sut.generateImageFilename()
        #expect(filename.hasPrefix("SnapForge_"), "Filename should start with 'SnapForge_'")
        #expect(filename.hasSuffix(".png"), "Default format should be .png")
    }

    @Test func generateImageFilenameJpegFormat() {
        let filename = sut.generateImageFilename(format: "jpeg")
        #expect(filename.hasSuffix(".jpeg"))
    }

    @Test func generateVideoFilenameDefaultFormat() {
        let filename = sut.generateVideoFilename()
        #expect(filename.hasPrefix("SnapForge_Recording_"))
        #expect(filename.hasSuffix(".mp4"))
    }

    @Test func generateVideoFilenameMovFormat() {
        let filename = sut.generateVideoFilename(format: "mov")
        #expect(filename.hasSuffix(".mov"))
    }

    @Test func filenamesHaveConsistentPrefix() {
        let filenames = (0..<10).map { _ in sut.generateImageFilename() }
        #expect(filenames.allSatisfy { $0.hasPrefix("SnapForge_") })
    }

    // MARK: - Directory Management

    @Test func snapForgeDirectoryPath() {
        let dir = sut.snapForgeDirectory
        #expect(dir.lastPathComponent == "SnapForge")
    }

    @Test func defaultSaveURLIsNotEmpty() {
        let url = sut.defaultSaveURL
        #expect(url.path.isEmpty == false)
    }

    // MARK: - Image Save/Load

    @Test func saveImageCreatesFile() throws {
        let image = NSImage(size: NSSize(width: 100, height: 100))
        image.lockFocus()
        NSColor.red.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: 100, height: 100))
        image.unlockFocus()

        let filename = "test_capture_\(UUID().uuidString).png"
        let savedURL = try sut.saveImage(image, filename: filename)

        #expect(FileManager.default.fileExists(atPath: savedURL.path))

        // Cleanup
        try? FileManager.default.removeItem(at: savedURL)
    }

    @Test func saveImagePngHasContent() throws {
        let image = NSImage(size: NSSize(width: 50, height: 50))
        image.lockFocus()
        NSColor.blue.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: 50, height: 50))
        image.unlockFocus()

        let filename = "test_content_\(UUID().uuidString).png"
        let savedURL = try sut.saveImage(image, filename: filename)

        let data = try Data(contentsOf: savedURL)
        #expect(data.count > 0, "Saved PNG should have content")

        // Cleanup
        try? FileManager.default.removeItem(at: savedURL)
    }
}
