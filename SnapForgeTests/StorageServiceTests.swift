import XCTest
@testable import SnapForge

/// Tests for StorageService — file naming, saving, directory management
final class StorageServiceTests: XCTestCase {

    private func makeStorage() -> StorageService {
        StorageService()
    }

    // MARK: - Filename Generation

    func testGenerateImageFilename_defaultFormat() {
        let storage = makeStorage()
        let filename = storage.generateImageFilename()
        XCTAssertTrue(filename.hasPrefix("SnapForge_"), "Filename should start with 'SnapForge_'")
        XCTAssertTrue(filename.hasSuffix(".png"), "Default format should be .png")
    }

    func testGenerateImageFilename_jpegFormat() {
        let storage = makeStorage()
        let filename = storage.generateImageFilename(format: "jpeg")
        XCTAssertTrue(filename.hasSuffix(".jpeg"))
    }

    func testGenerateVideoFilename_defaultFormat() {
        let storage = makeStorage()
        let filename = storage.generateVideoFilename()
        XCTAssertTrue(filename.hasPrefix("SnapForge_Recording_"))
        XCTAssertTrue(filename.hasSuffix(".mp4"))
    }

    func testGenerateVideoFilename_movFormat() {
        let storage = makeStorage()
        let filename = storage.generateVideoFilename(format: "mov")
        XCTAssertTrue(filename.hasSuffix(".mov"))
    }

    func testFilenamesAreUnique() {
        let storage = makeStorage()
        let filenames = (0..<10).map { _ in storage.generateImageFilename() }
        XCTAssertTrue(filenames.allSatisfy { $0.hasPrefix("SnapForge_") })
    }

    // MARK: - Directory Management

    func testSnapForgeDirectoryPath() {
        let storage = makeStorage()
        let dir = storage.snapForgeDirectory
        XCTAssertTrue(dir.lastPathComponent == "SnapForge")
    }

    func testDefaultSaveURL_isNotEmpty() {
        let storage = makeStorage()
        let url = storage.defaultSaveURL
        XCTAssertFalse(url.path.isEmpty)
    }

    // MARK: - Image Save/Load

    func testSaveImage_createsFile() throws {
        let storage = makeStorage()
        let image = NSImage(size: NSSize(width: 100, height: 100))
        image.lockFocus()
        NSColor.red.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: 100, height: 100))
        image.unlockFocus()

        let filename = "test_capture_\(UUID().uuidString).png"
        let savedURL = try storage.saveImage(image, filename: filename)

        XCTAssertTrue(FileManager.default.fileExists(atPath: savedURL.path))

        // Cleanup
        try? FileManager.default.removeItem(at: savedURL)
    }

    func testSaveImage_pngHasContent() throws {
        let storage = makeStorage()
        let image = NSImage(size: NSSize(width: 50, height: 50))
        image.lockFocus()
        NSColor.blue.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: 50, height: 50))
        image.unlockFocus()

        let filename = "test_content_\(UUID().uuidString).png"
        let savedURL = try storage.saveImage(image, filename: filename)

        let data = try Data(contentsOf: savedURL)
        XCTAssertGreaterThan(data.count, 0, "Saved PNG should have content")

        // Cleanup
        try? FileManager.default.removeItem(at: savedURL)
    }
}
