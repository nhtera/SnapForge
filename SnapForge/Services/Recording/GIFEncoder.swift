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

        // Cap frames to prevent OOM on long recordings (~30s at 15fps)
        let maxFrames = 450
        let cappedTotalFrames = min(totalFrames, maxFrames)

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
            cappedTotalFrames,
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

        // Use batch API to extract frames with a single internal reader.
        // The async image(at:) API creates a new reader per call,
        // exhausting resources after ~30 frames (AVError -11832 / -12431).
        let requestedTimes = (0..<cappedTotalFrames).map { i in
            NSValue(time: CMTime(seconds: Double(i) * frameDuration, preferredTimescale: 600))
        }

        let batchCtx = GIFBatchContext(
            destination: destination,
            frameProperties: frameProperties as CFDictionary,
            totalFrames: cappedTotalFrames,
            progress: progress
        )

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            generator.generateCGImagesAsynchronously(forTimes: requestedTimes) { _, image, _, result, error in
                batchCtx.processedCount += 1

                if result == .succeeded, let image {
                    autoreleasepool {
                        CGImageDestinationAddImage(batchCtx.destination, image, batchCtx.frameProperties)
                    }
                    batchCtx.framesAdded += 1
                } else if let error {
                    AppLogger.export.warning("GIF frame \(batchCtx.processedCount) extraction failed: \(error.localizedDescription)")
                }

                batchCtx.progress?(batchCtx.processedCount, batchCtx.totalFrames)

                if batchCtx.processedCount >= batchCtx.totalFrames {
                    continuation.resume()
                }
            }
        }

        guard batchCtx.framesAdded > 0 else {
            throw GIFEncoderError.invalidInput("No frames could be extracted from video")
        }

        // Finalize
        guard CGImageDestinationFinalize(destination) else {
            throw GIFEncoderError.failedToFinalize
        }

        AppLogger.export.info("GIF encoded: \(batchCtx.framesAdded)/\(cappedTotalFrames) frames → \(outputURL.lastPathComponent)")
    }
}

// MARK: - Batch Context

/// Thread-safe context for batch GIF frame extraction.
/// Protected by NSLock since Apple docs don't guarantee sequential callbacks.
private final class GIFBatchContext: @unchecked Sendable {
    let destination: CGImageDestination
    let frameProperties: CFDictionary
    let totalFrames: Int
    let progress: GIFEncoder.ProgressHandler?
    private let lock = NSLock()
    private var _framesAdded = 0
    private var _processedCount = 0

    var framesAdded: Int {
        get { lock.withLock { _framesAdded } }
        set { lock.withLock { _framesAdded = newValue } }
    }

    var processedCount: Int {
        get { lock.withLock { _processedCount } }
        set { lock.withLock { _processedCount = newValue } }
    }

    init(
        destination: CGImageDestination,
        frameProperties: CFDictionary,
        totalFrames: Int,
        progress: GIFEncoder.ProgressHandler?
    ) {
        self.destination = destination
        self.frameProperties = frameProperties
        self.totalFrames = totalFrames
        self.progress = progress
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
