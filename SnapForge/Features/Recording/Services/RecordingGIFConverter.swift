import Foundation

/// Handles GIF conversion from recorded video files
@MainActor
final class RecordingGIFConverter {

    /// Convert video to GIF, delete source on success. Returns GIF URL on success.
    func convert(videoURL: URL) async -> URL? {
        let encoder = GIFEncoder()
        let gifURL = videoURL.deletingPathExtension().appendingPathExtension("gif")
        let defaults = UserDefaults.standard
        let config = GIFEncoder.Configuration(
            fps: defaults.integer(forKey: SettingsKey.gifFPS),
            maxWidth: defaults.integer(forKey: SettingsKey.gifMaxWidth),
            loopCount: defaults.integer(forKey: SettingsKey.gifLoopCount),
            quality: Float(defaults.double(forKey: SettingsKey.gifQuality))
        )
        do {
            try await encoder.encode(
                inputURL: videoURL,
                outputURL: gifURL,
                config: config
            ) { @Sendable framesProcessed, totalFrames in
                print("GIF encoding: \(framesProcessed)/\(totalFrames)")
            }
            print("✅ GIF saved: \(gifURL.lastPathComponent)")
            try? FileManager.default.removeItem(at: videoURL)
            return gifURL
        } catch {
            print("❌ GIF encoding failed: \(error)")
            return nil
        }
    }
}
