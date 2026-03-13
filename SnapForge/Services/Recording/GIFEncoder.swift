import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Converts MP4 video files to animated GIF format.
final class GIFEncoder {

    struct Configuration {
        var fps: Int = 15              // Target GIF framerate
        var maxWidth: Int = 640        // Max width (downscale if larger)
        var loopCount: Int = 0         // 0 = infinite loop
        var quality: Float = 0.8       // 0.0–1.0

        static let low = Configuration(fps: 10, maxWidth: 480, quality: 0.5)
        static let medium = Configuration(fps: 15, maxWidth: 640, quality: 0.8)
        static let high = Configuration(fps: 24, maxWidth: 1280, quality: 1.0)
    }

    /// Progress callback: (framesProcessed, totalFrames)
    typealias ProgressHandler = (Int, Int) -> Void

    /// Convert MP4 video at `inputURL` to animated GIF at `outputURL`.
    func encode(
        inputURL: URL,
        outputURL: URL,
        config: Configuration = .medium,
        progress: ProgressHandler? = nil
    ) async throws {
        let asset = AVURLAsset(url: inputURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        guard durationSeconds > 0 else {
            throw GIFEncoderError.invalidInput("Video has zero duration")
        }

        // Calculate frame count and times
        let totalFrames = Int(durationSeconds * Double(config.fps))
        guard totalFrames > 0 else {
            throw GIFEncoderError.invalidInput("No frames to extract")
        }

        let frameDuration = 1.0 / Double(config.fps)

        // Set up AVAssetImageGenerator
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: frameDuration / 2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: frameDuration / 2, preferredTimescale: 600)

        // Determine output size
        let videoTrack = try await asset.loadTracks(withMediaType: .video).first
        let naturalSize = try await videoTrack?.load(.naturalSize) ?? CGSize(width: 640, height: 480)
        let scale = min(1.0, CGFloat(config.maxWidth) / naturalSize.width)
        let outputSize = CGSize(
            width: floor(naturalSize.width * scale),
            height: floor(naturalSize.height * scale)
        )
        generator.maximumSize = outputSize

        // Create GIF destination
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.gif.identifier as CFString,
            totalFrames,
            nil
        ) else {
            throw GIFEncoderError.failedToCreateDestination
        }

        // Set GIF file-level properties (loop count)
        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: config.loopCount
            ]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        // Frame delay property
        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: frameDuration
            ]
        ]

        // Extract frames and add to GIF
        for i in 0..<totalFrames {
            let time = CMTime(seconds: Double(i) * frameDuration, preferredTimescale: 600)

            let cgImage: CGImage
            do {
                let (image, _) = try await generator.image(at: time)
                cgImage = image
            } catch {
                print("⚠️ GIF frame \(i) extraction failed: \(error)")
                continue
            }

            CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)
            progress?(i + 1, totalFrames)
        }

        // Finalize
        guard CGImageDestinationFinalize(destination) else {
            throw GIFEncoderError.failedToFinalize
        }

        print("✅ GIF encoded: \(totalFrames) frames → \(outputURL.lastPathComponent)")
    }
}

// MARK: - Errors

enum GIFEncoderError: LocalizedError {
    case invalidInput(String)
    case failedToCreateDestination
    case failedToFinalize

    var errorDescription: String? {
        switch self {
        case .invalidInput(let msg): return "Invalid input: \(msg)"
        case .failedToCreateDestination: return "Failed to create GIF file"
        case .failedToFinalize: return "Failed to finalize GIF"
        }
    }
}
