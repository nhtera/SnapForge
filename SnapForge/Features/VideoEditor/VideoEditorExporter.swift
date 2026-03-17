import AVFoundation
import Foundation

/// Handles video export operations with support for quality, dimensions, and audio settings.
@MainActor
enum VideoEditorExporter {

    // MARK: - Export Methods

    /// Export trimmed video with full export settings (quality, dimensions, audio).
    static func exportTrimmed(
        state: VideoEditorState,
        to outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let timeRange = CMTimeRange(
            start: CMTime(seconds: state.trimStart, preferredTimescale: 600),
            end: CMTime(seconds: state.trimEnd, preferredTimescale: 600)
        )

        let settings = state.exportSettings

        // Determine if we need a composition
        let hasBackground = state.backgroundStyle != .none && state.backgroundPadding > 0
        let needsComposition = settings.audioMode == .mute
            || settings.audioMode == .custom
            || settings.dimensionPreset != .original
            || hasBackground

        if needsComposition {
            try await exportWithComposition(
                state: state,
                to: outputURL,
                timeRange: timeRange,
                progress: progress
            )
        } else {
            try await exportSimple(
                state: state,
                to: outputURL,
                timeRange: timeRange,
                progress: progress
            )
        }
    }

    // MARK: - Simple Export (trim + quality only)

    private static func exportSimple(
        state: VideoEditorState,
        to outputURL: URL,
        timeRange: CMTimeRange,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let exportSession = AVAssetExportSession(
            asset: state.asset,
            presetName: state.exportSettings.quality.exportPreset
        ) else {
            throw ExportError.sessionCreationFailed
        }

        try? FileManager.default.removeItem(at: outputURL)

        exportSession.timeRange = timeRange

        let fileType = outputFileType(for: state.videoURL.pathExtension)
        try await runExportSession(exportSession, to: outputURL, as: fileType, progress: progress)

        print("✅ Exported video: \(outputURL.lastPathComponent)")
    }

    // MARK: - Composition Export (audio/dimensions)

    private static func exportWithComposition(
        state: VideoEditorState,
        to outputURL: URL,
        timeRange: CMTimeRange,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let asset = state.asset
        let settings = state.exportSettings

        let composition = AVMutableComposition()

        // Add video track
        guard let sourceVideoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExportError.sessionCreationFailed
        }

        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.sessionCreationFailed
        }

        try compositionVideoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: .zero)

        // Copy preferred transform
        let transform = try await sourceVideoTrack.load(.preferredTransform)
        compositionVideoTrack.preferredTransform = transform

        // Add audio track (unless muted)
        var audioMix: AVMutableAudioMix?

        if settings.shouldIncludeAudio,
           let sourceAudioTrack = try await asset.loadTracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(
               withMediaType: .audio,
               preferredTrackID: kCMPersistentTrackID_Invalid
           )
        {
            try compositionAudioTrack.insertTimeRange(timeRange, of: sourceAudioTrack, at: .zero)

            // Apply custom volume if needed
            if settings.audioMode == .custom && settings.audioVolume != 1.0 {
                let mix = AVMutableAudioMix()
                let params = AVMutableAudioMixInputParameters(track: compositionAudioTrack)
                params.setVolume(settings.effectiveVolume, at: .zero)
                mix.inputParameters = [params]
                audioMix = mix
            }
        }

        // Video composition — background compositing or dimension scaling
        let hasBackground = state.backgroundStyle != .none && state.backgroundPadding > 0
        var videoComposition: AVMutableVideoComposition?
        var forceHighestQuality = false

        if hasBackground {
            // Use custom compositor for background rendering
            let naturalSize = state.naturalSize
            let padding = state.backgroundPadding
            var paddedSize = CGSize(
                width: naturalSize.width + padding * 2,
                height: naturalSize.height + padding * 2
            )

            // Apply dimension scaling on top of padded size
            var scaledVideoSize = naturalSize
            var scaledPadding = padding
            if settings.dimensionPreset != .original, let scaleFactor = settings.dimensionPreset.scaleFactor {
                paddedSize = CGSize(
                    width: CGFloat(Int(paddedSize.width * scaleFactor) - (Int(paddedSize.width * scaleFactor) % 2)),
                    height: CGFloat(Int(paddedSize.height * scaleFactor) - (Int(paddedSize.height * scaleFactor) % 2))
                )
                scaledVideoSize = CGSize(
                    width: naturalSize.width * scaleFactor,
                    height: naturalSize.height * scaleFactor
                )
                scaledPadding = padding * scaleFactor
            }

            let vc = AVMutableVideoComposition()
            vc.renderSize = paddedSize
            vc.frameDuration = CMTime(value: 1, timescale: 30)
            vc.customVideoCompositorClass = VideoBackgroundCompositor.self

            let bgInstruction = BackgroundCompositionInstruction(
                timeRange: CMTimeRange(start: .zero, duration: timeRange.duration),
                trackID: compositionVideoTrack.trackID,
                backgroundStyle: state.backgroundStyle,
                padding: scaledPadding,
                cornerRadius: state.backgroundCornerRadius,
                shadowIntensity: state.backgroundShadowIntensity,
                videoSize: scaledVideoSize
            )

            vc.instructions = [bgInstruction]
            videoComposition = vc
            forceHighestQuality = true // Custom compositor requires highest quality preset

        } else if settings.dimensionPreset != .original {
            // Standard dimension scaling (no background)
            let naturalSize = state.naturalSize
            let exportSize = settings.exportSize(from: naturalSize)

            let vc = AVMutableVideoComposition()
            vc.renderSize = exportSize
            vc.frameDuration = CMTime(value: 1, timescale: 30)

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(
                start: .zero,
                duration: timeRange.duration
            )

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(
                assetTrack: compositionVideoTrack
            )

            // Scale transform — combine original transform with scaling
            let scaleX = exportSize.width / naturalSize.width
            let scaleY = exportSize.height / naturalSize.height
            let scaleTransform = transform.concatenating(CGAffineTransform(scaleX: scaleX, y: scaleY))
            layerInstruction.setTransform(scaleTransform, at: .zero)

            instruction.layerInstructions = [layerInstruction]
            vc.instructions = [instruction]

            videoComposition = vc
        }

        // Create export session — custom compositor requires highest quality preset
        let presetName = forceHighestQuality
            ? AVAssetExportPresetHighestQuality
            : settings.quality.exportPreset
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: presetName
        ) else {
            throw ExportError.sessionCreationFailed
        }

        try? FileManager.default.removeItem(at: outputURL)

        if let audioMix {
            exportSession.audioMix = audioMix
        }
        if let videoComposition {
            exportSession.videoComposition = videoComposition
        }

        let fileType = outputFileType(for: state.videoURL.pathExtension)
        try await runExportSession(exportSession, to: outputURL, as: fileType, progress: progress)

        print("✅ Exported video with settings: \(outputURL.lastPathComponent)")
    }

    // MARK: - Safe Export Runner

    /// Runs an AVAssetExportSession using the modern export(to:as:) API.
    /// Progress is polled from a Task on the main actor — both the polling
    /// and export cooperatively interleave at suspension points (no data race).
    /// export(to:as:) throws on failure, eliminating need for deprecated
    /// status/error checks.
    private static func runExportSession(
        _ session: AVAssetExportSession,
        to outputURL: URL,
        as fileType: AVFileType,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let progressTask = Task {
            while !Task.isCancelled {
                progress(Double(session.progress))
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        defer {
            progressTask.cancel()
            progress(1.0)
        }

        try await session.export(to: outputURL, as: fileType)
    }

    // MARK: - Replace Original

    /// Replace the original video file with the exported version.
    static func replaceOriginal(
        state: VideoEditorState,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(state.videoURL.pathExtension)

        try await exportTrimmed(state: state, to: tempURL, progress: progress)

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
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try? FileManager.default.moveItem(at: backupURL, to: originalURL)
            }
            throw error
        }
    }

    /// Save exported video as a copy next to the original.
    static func saveAsCopy(
        state: VideoEditorState,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let copyURL = generateCopyURL(from: state.videoURL)
        try await exportTrimmed(state: state, to: copyURL, progress: progress)
        return copyURL
    }

    // MARK: - Helpers

    static func generateCopyFilename(from originalURL: URL) -> String {
        let baseName = originalURL.deletingPathExtension().lastPathComponent
        let ext = originalURL.pathExtension
        return "\(baseName)_edited.\(ext)"
    }

    static func generateCopyURL(from originalURL: URL) -> URL {
        let directory = originalURL.deletingLastPathComponent()
        let baseName = originalURL.deletingPathExtension().lastPathComponent
        let ext = originalURL.pathExtension
        var copyURL = directory.appendingPathComponent("\(baseName)_edited.\(ext)")

        var counter = 1
        while FileManager.default.fileExists(atPath: copyURL.path) {
            copyURL = directory.appendingPathComponent("\(baseName)_edited_\(counter).\(ext)")
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
            case .sessionCreationFailed: "Failed to create export session"
            case .exportFailed: "Video export failed"
            }
        }
    }
}
