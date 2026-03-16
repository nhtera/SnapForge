import AVFoundation
import Foundation

/// Handles video trimming and export operations for the SnapForge video editor.
@MainActor
enum VideoEditorExporter {

    // MARK: - Export Methods

    /// Export trimmed video to a specified output URL using modern async API.
    static func exportTrimmed(
        state: VideoEditorState,
        to outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let timeRange = CMTimeRange(
            start: CMTime(seconds: state.trimStart, preferredTimescale: 600),
            end: CMTime(seconds: state.trimEnd, preferredTimescale: 600)
        )

        guard let exportSession = AVAssetExportSession(
            asset: state.asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ExportError.sessionCreationFailed
        }

        // Remove existing file if present
        try? FileManager.default.removeItem(at: outputURL)

        // Configure trim range before export
        exportSession.timeRange = timeRange
        exportSession.outputURL = outputURL
        exportSession.outputFileType = outputFileType(for: state.videoURL.pathExtension)

        // Monitor progress using modern states() async stream
        let progressTask = Task {
            for await exportState in exportSession.states(updateInterval: 0.1) {
                if case .exporting(let p) = exportState {
                    progress(p.fractionCompleted)
                }
            }
        }

        // Use modern export(to:as:) API
        try await exportSession.export(
            to: outputURL,
            as: outputFileType(for: state.videoURL.pathExtension)
        )
        progressTask.cancel()
        progress(1.0)

        print("✅ Trimmed video exported: \(outputURL.lastPathComponent)")
    }

    /// Replace the original video file with the trimmed version.
    static func replaceOriginal(
        state: VideoEditorState,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(state.videoURL.pathExtension)

        try await exportTrimmed(state: state, to: tempURL, progress: progress)

        // Replace original with temp file
        let originalURL = state.videoURL
        let backupURL = originalURL.deletingLastPathComponent()
            .appendingPathComponent(".\(originalURL.lastPathComponent).backup")

        do {
            try? FileManager.default.removeItem(at: backupURL)
            try FileManager.default.moveItem(at: originalURL, to: backupURL)
            try FileManager.default.moveItem(at: tempURL, to: originalURL)
            try? FileManager.default.removeItem(at: backupURL)
            print("✅ Original video replaced: \(originalURL.lastPathComponent)")
        } catch {
            // Restore from backup on failure
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try? FileManager.default.moveItem(at: backupURL, to: originalURL)
            }
            throw error
        }
    }

    /// Save trimmed video as a copy next to the original.
    static func saveAsCopy(
        state: VideoEditorState,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let copyURL = generateCopyURL(from: state.videoURL)
        try await exportTrimmed(state: state, to: copyURL, progress: progress)
        return copyURL
    }

    // MARK: - Helpers

    /// Generate a copy filename with "_trimmed" suffix.
    static func generateCopyFilename(from originalURL: URL) -> String {
        let baseName = originalURL.deletingPathExtension().lastPathComponent
        let ext = originalURL.pathExtension
        return "\(baseName)_trimmed.\(ext)"
    }

    static func generateCopyURL(from originalURL: URL) -> URL {
        let directory = originalURL.deletingLastPathComponent()
        let baseName = originalURL.deletingPathExtension().lastPathComponent
        let ext = originalURL.pathExtension
        var copyURL = directory.appendingPathComponent("\(baseName)_trimmed.\(ext)")

        var counter = 1
        while FileManager.default.fileExists(atPath: copyURL.path) {
            copyURL = directory.appendingPathComponent("\(baseName)_trimmed_\(counter).\(ext)")
            counter += 1
        }
        return copyURL
    }

    private static func outputFileType(for pathExtension: String) -> AVFileType {
        switch pathExtension.lowercased() {
        case "mp4": .mp4
        case "mov": .mov
        default: .mp4
        }
    }

    // MARK: - Errors

    enum ExportError: Error, LocalizedError {
        case sessionCreationFailed
        case exportFailed

        var errorDescription: String? {
            switch self {
            case .sessionCreationFailed:
                "Failed to create export session"
            case .exportFailed:
                "Video export failed"
            }
        }
    }
}
