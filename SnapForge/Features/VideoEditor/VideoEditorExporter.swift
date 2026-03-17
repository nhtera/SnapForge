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
        exportSession.outputURL = outputURL
        exportSession.outputFileType = outputFileType(for: state.videoURL.pathExtension)

        try await runExportSession(exportSession, progress: progress)

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

        // Read source frame rate to preserve it in the exported composition
        let sourceFPS = try await sourceVideoTrack.load(.nominalFrameRate)
        let frameTimescale = max(Int32(ceil(sourceFPS)), 1)

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
            vc.frameDuration = CMTime(value: 1, timescale: frameTimescale)
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
            vc.frameDuration = CMTime(value: 1, timescale: frameTimescale)

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

        exportSession.outputURL = outputURL
        exportSession.outputFileType = outputFileType(for: state.videoURL.pathExtension)

        if let audioMix {
            exportSession.audioMix = audioMix
        }
        if let videoComposition {
            exportSession.videoComposition = videoComposition
        }

        try await runExportSession(exportSession, progress: progress)

        print("✅ Exported video with settings: \(outputURL.lastPathComponent)")
    }

    // MARK: - Safe Export Runner

    /// Runs an AVAssetExportSession using the legacy callback API wrapped in a
    /// checked continuation with a timer for progress polling.
    ///
    /// The modern `export(to:as:)` API crashes with EXC_BAD_ACCESS on internal
    /// AVFoundation threads when used with custom video compositors (FB16XXXXXX).
    /// The legacy callback API is the only stable option until Apple fixes this.
    private static func runExportSession(
        _ session: AVAssetExportSession,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        nonisolated(unsafe) let unsafeSession = session

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            nonisolated(unsafe) let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                progress(Double(unsafeSession.progress))
            }

            unsafeSession.exportAsynchronously {
                timer.invalidate()

                switch unsafeSession.status {
                case .completed:
                    progress(1.0)
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: unsafeSession.error ?? ExportError.exportFailed)
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                default:
                    continuation.resume(throwing: ExportError.exportFailed)
                }
            }
        }
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

        // Atomic replacement — avoids the race condition where original is removed
        // but the move fails, leaving the file permanently gone.
        _ = try FileManager.default.replaceItemAt(originalURL, withItemAt: tempURL)
        print("✅ Original video replaced: \(originalURL.lastPathComponent)")
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
