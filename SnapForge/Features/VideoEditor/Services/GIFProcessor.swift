import Foundation
import ImageIO
import UniformTypeIdentifiers
import AppKit

/// Metadata extracted from an animated GIF file via ImageIO.
struct GIFMetadata {
    let width: Int
    let height: Int
    let frameCount: Int
    let duration: Double
    let loopCount: Int
    let fileSize: Int64
    let frameDelays: [Double]

    var size: CGSize { CGSize(width: width, height: height) }
    var fps: Double { duration > 0 ? Double(frameCount) / duration : 0 }
}

/// GIF file operations: metadata reading, thumbnail extraction, and trim+resize export.
/// Uses ImageIO (CGImageSource/CGImageDestination) — AVFoundation cannot handle GIF files.
/// Not @MainActor — exportTrimmed runs heavy frame processing that must not block UI.
enum GIFProcessor {

    // MARK: - Metadata

    /// Read metadata from a GIF file (dimensions, frame count, per-frame delays, loop count).
    static func metadata(for url: URL) -> GIFMetadata? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { return nil }

        // Read dimensions from first frame
        guard let imageProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = imageProps[kCGImagePropertyPixelWidth] as? Int,
              let height = imageProps[kCGImagePropertyPixelHeight] as? Int
        else { return nil }

        // Read per-frame delays
        var frameDelays: [Double] = []
        for i in 0..<frameCount {
            let delay = frameDelay(for: source, at: i)
            frameDelays.append(delay)
        }

        let duration = frameDelays.reduce(0, +)

        // Read loop count from file-level GIF properties
        var loopCount = 0
        if let fileProps = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
           let gifDict = fileProps[kCGImagePropertyGIFDictionary] as? [CFString: Any],
           let loop = gifDict[kCGImagePropertyGIFLoopCount] as? Int {
            loopCount = loop
        }

        // File size
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0

        return GIFMetadata(
            width: width,
            height: height,
            frameCount: frameCount,
            duration: duration,
            loopCount: loopCount,
            fileSize: fileSize,
            frameDelays: frameDelays
        )
    }

    // MARK: - Thumbnail Extraction

    /// Extract evenly-spaced thumbnail frames for timeline display.
    static func extractThumbnails(from url: URL, count: Int, maxSize: CGSize) -> [NSImage] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [] }

        let totalFrames = CGImageSourceGetCount(source)
        guard totalFrames > 0 else { return [] }

        let step = max(1, totalFrames / count)
        var images: [NSImage] = []

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: max(maxSize.width, maxSize.height),
            kCGImageSourceCreateThumbnailFromImageAlways: true
        ]

        for i in stride(from: 0, to: totalFrames, by: step) {
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, i, thumbOptions as CFDictionary) {
                let image = NSImage(cgImage: cgImage, size: NSSize(width: maxSize.width, height: maxSize.height))
                images.append(image)
            }
            if images.count >= count { break }
        }

        return images
    }

    // MARK: - Export (Trim + Resize)

    /// Export a trimmed and/or resized GIF.
    /// Processes frames one at a time to minimize memory usage.
    static func exportTrimmed(
        sourceURL: URL,
        outputURL: URL,
        startFrame: Int,
        endFrame: Int,
        targetSize: CGSize?,
        onProgress: @escaping (Double) -> Void
    ) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            throw GIFProcessorError.failedToOpenSource
        }

        let totalSourceFrames = CGImageSourceGetCount(source)
        let clampedStart = max(0, startFrame)
        let clampedEnd = min(totalSourceFrames - 1, endFrame)
        guard clampedStart <= clampedEnd else {
            throw GIFProcessorError.invalidFrameRange
        }

        let outputFrameCount = clampedEnd - clampedStart + 1

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.gif.identifier as CFString,
            outputFrameCount,
            nil
        ) else {
            throw GIFProcessorError.failedToCreateDestination
        }

        // Copy global GIF properties (loop count)
        if let fileProps = CGImageSourceCopyProperties(source, nil) {
            CGImageDestinationSetProperties(destination, fileProps)
        }

        // Process frames one at a time
        for i in clampedStart...clampedEnd {
            autoreleasepool {
                guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { return }

                // Build per-frame properties (preserve original delay)
                let delay = frameDelay(for: source, at: i)
                let frameProps: [CFString: Any] = [
                    kCGImagePropertyGIFDictionary: [
                        kCGImagePropertyGIFDelayTime: delay,
                        kCGImagePropertyGIFUnclampedDelayTime: delay,
                    ]
                ]

                if let targetSize, targetSize.width > 0, targetSize.height > 0 {
                    // Resize frame
                    if let resized = resizeImage(cgImage, to: targetSize) {
                        CGImageDestinationAddImage(destination, resized, frameProps as CFDictionary)
                    } else {
                        CGImageDestinationAddImage(destination, cgImage, frameProps as CFDictionary)
                    }
                } else {
                    CGImageDestinationAddImage(destination, cgImage, frameProps as CFDictionary)
                }
            }

            let progress = Double(i - clampedStart + 1) / Double(outputFrameCount)
            onProgress(progress)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw GIFProcessorError.failedToFinalize
        }
    }

    // MARK: - Private Helpers

    /// Read the delay time for a specific frame from its GIF properties.
    private static func frameDelay(for source: CGImageSource, at index: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gifDict = props[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else { return 0.1 }

        // Prefer unclamped delay, fall back to clamped delay
        if let unclamped = gifDict[kCGImagePropertyGIFUnclampedDelayTime] as? Double, unclamped > 0 {
            return unclamped
        }
        if let delay = gifDict[kCGImagePropertyGIFDelayTime] as? Double, delay > 0 {
            return delay
        }
        return 0.1 // Default fallback
    }

    /// Resize a CGImage to the target size using CoreGraphics.
    private static func resizeImage(_ image: CGImage, to size: CGSize) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

// MARK: - Errors

enum GIFProcessorError: LocalizedError {
    case failedToOpenSource
    case failedToCreateDestination
    case failedToFinalize
    case invalidFrameRange

    var errorDescription: String? {
        switch self {
        case .failedToOpenSource: "Failed to open GIF file"
        case .failedToCreateDestination: "Failed to create GIF output"
        case .failedToFinalize: "Failed to finalize GIF export"
        case .invalidFrameRange: "Invalid frame range for GIF trim"
        }
    }
}
