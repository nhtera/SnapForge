import Foundation

/// Handles GIF conversion from recorded video files with progress UI
@MainActor
final class RecordingGIFConverter {
    private let progressPanel = RecordingGIFProgressPanel()

    /// Convert video to GIF. Returns GIF URL on success.
    /// - Parameter deleteSource: remove the source video after a successful conversion
    ///   (GIF recording mode). Pass `false` to keep the original (e.g. Quick Access "GIF").
    func convert(videoURL: URL, deleteSource: Bool = true) async -> URL? {
        let encoder = GIFEncoder()
        let gifURL = videoURL.deletingPathExtension().appendingPathExtension("gif")
        let defaults = UserDefaults.standard
        let config = GIFEncoder.Configuration(
            fps: defaults.integer(forKey: SettingsKey.gifFPS),
            maxWidth: defaults.integer(forKey: SettingsKey.gifMaxWidth),
            loopCount: defaults.integer(forKey: SettingsKey.gifLoopCount),
            quality: Float(defaults.double(forKey: SettingsKey.gifQuality))
        )

        progressPanel.show()
        defer { progressPanel.dismiss() }

        do {
            try await encoder.encode(
                inputURL: videoURL,
                outputURL: gifURL,
                config: config
            ) { @Sendable [weak self] framesProcessed, totalFrames in
                Task { @MainActor in
                    self?.progressPanel.update(
                        framesProcessed: framesProcessed,
                        totalFrames: totalFrames
                    )
                }
            }
            print("✅ GIF saved: \(gifURL.lastPathComponent)")
            if deleteSource {
                try? FileManager.default.removeItem(at: videoURL)
            }
            return gifURL
        } catch {
            print("❌ GIF encoding failed: \(error)")
            return nil
        }
    }
}
