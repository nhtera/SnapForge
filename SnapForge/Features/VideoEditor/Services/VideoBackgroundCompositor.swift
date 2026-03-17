import AVFoundation
import CoreImage
import SwiftUI

/// Custom video compositor that renders background (gradient/solid color),
/// padding, corner radius, and shadow into exported video frames.
/// Based on AVVideoCompositing protocol for per-frame rendering.
class VideoBackgroundCompositor: NSObject, @unchecked Sendable, AVVideoCompositing {

    // MARK: - AVVideoCompositing Protocol

    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
    }

    var supportsWideColorSourceFrames: Bool { false }
    var supportsHDRSourceFrames: Bool { false }

    private var renderContext: AVVideoCompositionRenderContext?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let queue = DispatchQueue(label: "com.snapforge.backgroundcompositor")

    private var cachedWallpaperURL: URL?
    private var cachedWallpaperSize: CGSize?
    private var cachedWallpaperImage: CIImage?

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        queue.sync {
            renderContext = newRenderContext
            // Clear cache if size changed
            if cachedWallpaperSize != newRenderContext.size {
                cachedWallpaperImage = nil
            }
        }
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        queue.async { [weak self] in
            self?.processRequest(request)
        }
    }

    func cancelAllPendingVideoCompositionRequests() {}

    // MARK: - Frame Processing

    private func processRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? BackgroundCompositionInstruction else {
            request.finish(with: CompositorError.invalidInstruction)
            return
        }

        // Try requested track ID first, then fall back to any available track.
        // Track ID mismatch can happen when AVFoundation reassigns IDs during composition.
        let sourceBuffer: CVPixelBuffer
        if let buffer = request.sourceFrame(byTrackID: instruction.trackID) {
            sourceBuffer = buffer
        } else {
            let availableTrackIDs = request.sourceTrackIDs.map(\.int32Value)
            if let firstTrackID = availableTrackIDs.first,
               let fallbackBuffer = request.sourceFrame(byTrackID: firstTrackID) {
                sourceBuffer = fallbackBuffer
            } else {
                print("❌ Compositor: no source frame. Requested trackID=\(instruction.trackID), available=\(request.sourceTrackIDs)")
                request.finish(with: CompositorError.noSourceFrame)
                return
            }
        }

        // If no background active, pass through directly
        guard instruction.hasBackground else {
            request.finish(withComposedVideoFrame: sourceBuffer)
            return
        }

        // Apply background effect
        guard let outputBuffer = applyBackground(
            to: sourceBuffer,
            instruction: instruction
        ) else {
            request.finish(withComposedVideoFrame: sourceBuffer)
            return
        }

        request.finish(withComposedVideoFrame: outputBuffer)
    }

    // MARK: - Background Rendering

    private func applyBackground(
        to sourceBuffer: CVPixelBuffer,
        instruction: BackgroundCompositionInstruction
    ) -> CVPixelBuffer? {
        var videoImage = CIImage(cvPixelBuffer: sourceBuffer)

        // Scale source frame to match expected video size (dimension scaling)
        let sourceW = videoImage.extent.width
        let sourceH = videoImage.extent.height
        let targetW = instruction.videoSize.width
        let targetH = instruction.videoSize.height
        if abs(sourceW - targetW) > 1 || abs(sourceH - targetH) > 1 {
            let scaleX = targetW / sourceW
            let scaleY = targetH / sourceH
            videoImage = videoImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        }

        // Apply corner radius to video frame
        if instruction.cornerRadius > 0 {
            videoImage = applyCornerRadius(
                to: videoImage,
                cornerRadius: instruction.cornerRadius,
                videoSize: instruction.videoSize
            )
        }

        // Translate video to center with padding
        let translatedVideo = videoImage.transformed(
            by: CGAffineTransform(
                translationX: instruction.padding,
                y: instruction.padding
            )
        )

        // Create background
        let background = createBackground(
            style: instruction.backgroundStyle,
            size: instruction.paddedSize
        )

        // Apply shadow if needed
        var composedImage: CIImage
        if instruction.shadowIntensity > 0 {
            let shadowRadius = instruction.shadowIntensity * 40
            let shadowImage = translatedVideo.applyingGaussianBlur(sigma: Double(shadowRadius))
                .cropped(to: CGRect(origin: .zero, size: instruction.paddedSize))
            let shadowWithOpacity = shadowImage.applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(instruction.shadowIntensity * 0.8)),
                ]
            )
            composedImage = translatedVideo
                .composited(over: shadowWithOpacity)
                .composited(over: background)
        } else {
            composedImage = translatedVideo.composited(over: background)
        }

        // Render to output buffer
        guard let renderContext,
              let outputBuffer = renderContext.newPixelBuffer()
        else { return nil }

        ciContext.render(composedImage, to: outputBuffer)
        return outputBuffer
    }

    // MARK: - Corner Radius

    private func applyCornerRadius(to image: CIImage, cornerRadius: CGFloat, videoSize: CGSize) -> CIImage {
        let extent = image.extent

        // Create rounded rect mask using CGContext
        guard let cgContext = CGContext(
            data: nil,
            width: Int(extent.width),
            height: Int(extent.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(extent.width) * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        // Scale corner radius proportionally
        let scaleFactor = min(extent.width, extent.height) / min(videoSize.width, videoSize.height)
        let scaledRadius = min(cornerRadius * scaleFactor, min(extent.width, extent.height) / 2)

        cgContext.setFillColor(CGColor.white)
        let path = CGPath(
            roundedRect: CGRect(origin: .zero, size: CGSize(width: extent.width, height: extent.height)),
            cornerWidth: scaledRadius,
            cornerHeight: scaledRadius,
            transform: nil
        )
        cgContext.addPath(path)
        cgContext.fillPath()

        guard let maskCGImage = cgContext.makeImage() else { return image }
        let maskImage = CIImage(cgImage: maskCGImage)

        guard let blendFilter = CIFilter(name: "CIBlendWithAlphaMask") else { return image }
        let transparent = CIImage(color: .clear).cropped(to: extent)
        blendFilter.setValue(image, forKey: kCIInputImageKey)
        blendFilter.setValue(transparent, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(maskImage, forKey: kCIInputMaskImageKey)

        return blendFilter.outputImage ?? image
    }

    // MARK: - Background Creation

    private func createBackground(style: VideoBackgroundStyle, size: CGSize) -> CIImage {
        let rect = CGRect(origin: .zero, size: size)

        switch style {
        case .none:
            return CIImage(color: .clear).cropped(to: rect)

        case .gradient(let preset):
            guard let filter = CIFilter(name: "CILinearGradient") else {
                return CIImage(color: .black).cropped(to: rect)
            }
            filter.setValue(CIVector(x: 0, y: size.height), forKey: "inputPoint0")
            filter.setValue(CIVector(x: size.width, y: 0), forKey: "inputPoint1")

            let color0 = CIColor(color: NSColor(preset.colors[0])) ?? CIColor.black
            let color1 = CIColor(color: NSColor(preset.colors[1])) ?? CIColor.white
            filter.setValue(color0, forKey: "inputColor0")
            filter.setValue(color1, forKey: "inputColor1")

            return filter.outputImage?.cropped(to: rect) ?? CIImage(color: .black).cropped(to: rect)

        case .solidColor(let color):
            let ciColor = CIColor(color: NSColor(color)) ?? CIColor.white
            return CIImage(color: ciColor).cropped(to: rect)

        case .wallpaper(let url):
            // Use cached wallpaper if available
            if let cached = cachedWallpaperImage,
               cachedWallpaperURL == url,
               cachedWallpaperSize == size {
                return cached
            }

            // Load and scale to fill
            guard let image = CIImage(contentsOf: url) else {
                return CIImage(color: .black).cropped(to: rect)
            }
            let scaleX = size.width / image.extent.width
            let scaleY = size.height / image.extent.height
            let scale = max(scaleX, scaleY)
            let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let offsetX = (scaled.extent.width - size.width) / 2
            let offsetY = (scaled.extent.height - size.height) / 2
            let result = scaled
                .cropped(to: CGRect(x: offsetX, y: offsetY, width: size.width, height: size.height))
                .transformed(by: CGAffineTransform(translationX: -offsetX, y: -offsetY))

            // Cache for subsequent frames
            cachedWallpaperURL = url
            cachedWallpaperSize = size
            cachedWallpaperImage = result

            return result
        }
    }

    // MARK: - Errors

    enum CompositorError: Error, LocalizedError {
        case invalidInstruction
        case noSourceFrame

        var errorDescription: String? {
            switch self {
            case .invalidInstruction: "Invalid composition instruction"
            case .noSourceFrame: "No source video frame available"
            }
        }
    }
}

// MARK: - Background Composition Instruction

/// Custom instruction carrying background rendering parameters per-frame.
class BackgroundCompositionInstruction: NSObject, @unchecked Sendable, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let trackID: CMPersistentTrackID
    let backgroundStyle: VideoBackgroundStyle
    let padding: CGFloat
    let cornerRadius: CGFloat
    let shadowIntensity: CGFloat
    let videoSize: CGSize
    let paddedSize: CGSize
    let hasBackground: Bool

    var enablePostProcessing: Bool { true }
    var containsTweening: Bool { true }
    var requiredSourceTrackIDs: [NSValue]? {
        [NSNumber(value: trackID)]
    }
    var passthroughTrackID: CMPersistentTrackID { kCMPersistentTrackID_Invalid }

    init(
        timeRange: CMTimeRange,
        trackID: CMPersistentTrackID,
        backgroundStyle: VideoBackgroundStyle,
        padding: CGFloat,
        cornerRadius: CGFloat,
        shadowIntensity: CGFloat,
        videoSize: CGSize
    ) {
        self.timeRange = timeRange
        self.trackID = trackID
        self.backgroundStyle = backgroundStyle
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.shadowIntensity = shadowIntensity
        self.videoSize = videoSize
        self.hasBackground = backgroundStyle != .none && padding > 0
        self.paddedSize = hasBackground
            ? CGSize(width: videoSize.width + padding * 2, height: videoSize.height + padding * 2)
            : videoSize
        super.init()
    }
}
