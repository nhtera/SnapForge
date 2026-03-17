import Testing
import Foundation
import AVFoundation
@testable import SnapForge

/// Tests for VideoEditorExporter — filename generation, URL helpers, file type mapping, error types
@MainActor
struct VideoEditorExporterTests {

    // MARK: - generateCopyFilename

    @Test func generateCopyFilenameAppendsEdited() {
        let url = URL(fileURLWithPath: "/tmp/video.mp4")
        let filename = VideoEditorExporter.generateCopyFilename(from: url)
        #expect(filename == "video_edited.mp4")
    }

    @Test func generateCopyFilenamePreservesExtension() {
        let url = URL(fileURLWithPath: "/tmp/recording.mov")
        let filename = VideoEditorExporter.generateCopyFilename(from: url)
        #expect(filename == "recording_edited.mov")
    }

    @Test func generateCopyFilenameHandlesMultipleDots() {
        let url = URL(fileURLWithPath: "/tmp/my.screen.recording.mp4")
        let filename = VideoEditorExporter.generateCopyFilename(from: url)
        #expect(filename == "my.screen.recording_edited.mp4")
    }

    // MARK: - generateCopyURL

    @Test func generateCopyURLPreservesDirectory() {
        let url = URL(fileURLWithPath: "/tmp/test_video.mp4")
        let copyURL = VideoEditorExporter.generateCopyURL(from: url)
        #expect(copyURL.deletingLastPathComponent().path == "/tmp")
    }

    @Test func generateCopyURLAppendsEditedSuffix() {
        let uniqueName = UUID().uuidString
        let url = URL(fileURLWithPath: "/tmp/\(uniqueName).mp4")
        let copyURL = VideoEditorExporter.generateCopyURL(from: url)
        #expect(copyURL.lastPathComponent == "\(uniqueName)_edited.mp4")
    }

    @Test func generateCopyURLIncrementsWhenFileExists() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let baseName = "test_increment_\(UUID().uuidString)"
        let editedURL = tempDir.appendingPathComponent("\(baseName)_edited.mp4")

        // Create the _edited file so the generator must increment
        FileManager.default.createFile(atPath: editedURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: editedURL) }

        let originalURL = tempDir.appendingPathComponent("\(baseName).mp4")
        let copyURL = VideoEditorExporter.generateCopyURL(from: originalURL)
        #expect(copyURL.lastPathComponent == "\(baseName)_edited_1.mp4")
    }

    // MARK: - ExportError

    @Test func exportErrorDescriptions() {
        let sessionError = VideoEditorExporter.ExportError.sessionCreationFailed
        let exportError = VideoEditorExporter.ExportError.exportFailed

        #expect(sessionError.errorDescription == "Failed to create export session")
        #expect(exportError.errorDescription == "Video export failed")
    }

    @Test func exportErrorConformsToLocalizedError() {
        let error: any LocalizedError = VideoEditorExporter.ExportError.exportFailed
        #expect(error.errorDescription != nil)
    }
}
