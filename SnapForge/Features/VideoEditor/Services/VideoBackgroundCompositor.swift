import AVFoundation
import CoreImage
import SwiftUI

/// Custom video compositor that renders background (gradient/solid color),
/// padding, corner radius, and shadow into exported video frames.
/// Based on AVVideoCompositing protocol for per-frame rendering.
///
/// Performance optimizations:
/// - Corner radius mask cached across frames (same size = same mask)
/// - Shadow rendered from shape (rounded rect), not video content — cached across frames
/// - Background image cached (gradient/solid/wallpaper are static)
/// - autoreleasepool per frame to prevent intermediate CIImage/CGImage accumulation
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

    // MARK: - Cached Assets (created once, reused every frame)

    /// Wallpaper image cache
    private var cachedWallpaperURL: URL?
    private var cachedWallpaperSize: CGSize?
    private var cachedWallpaperImage: CIImage?

    /// Corner radius mask — identical for every frame at the same video size
    private var cachedMaskImage: CIImage?
    private var cachedMaskSize: CGSize?
    private var cachedMaskRadius: CGFloat?

    /// Pre-computed shadow from rounded rectangle shape — identical every frame
    private var cachedShadowImage: CIImage?
    private var cachedShadowVideoSize: CGSize?
    private var cachedShadowPadding: CGFloat?
    private var cachedShadowRadius: CGFloat?
    private var cachedShadowIntensity: CGFloat?

    /// Background image cache (gradient/solid are static)
    private var cachedBackground: CIImage?
    private var cachedBackgroundSize: CGSize?
    private var cachedBackgroundStyleID: String?

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        queue.async { [self] in
            let sizeChanged = renderContext?.size != newRenderContext.size
            renderContext = newRenderContext

            // Only clear caches if render size changed
            if sizeChanged {
                cachedWallpaperURL = nil
                cachedWallpaperSize = nil
                cachedWallpaperImage = nil
                cachedMaskImage = nil
                cachedShadowImage = nil
                cachedBackground = nil
            }
        }
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        queue.async { [weak self] in
            // autoreleasepool prevents CIImage/CGImage intermediates from accumulating
            // across frames — without this, memory grows unbounded during export
            autoreleasepool {
                self?.processRequest(request)
            }
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

        // Apply corner radius to video frame (mask is cached)
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

        // Get cached background
        let background = getOrCreateBackground(
            style: instruction.backgroundStyle,
            size: instruction.paddedSize
        )

        // Compose with cached shadow or direct composition
        var composedImage: CIImage
        if instruction.shadowIntensity > 0 {
            let shadow = getOrCreateShadow(instruction: instruction)
            composedImage = translatedVideo
                .composited(over: shadow)
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

    // MARK: - Corner Radius (Cached Mask)

    private func applyCornerRadius(to image: CIImage, cornerRadius: CGFloat, videoSize: CGSize) -> CIImage {
        let extent = image.extent
        let maskImage = getOrCreateMask(extent: extent, cornerRadius: cornerRadius, videoSize: videoSize)

        guard let blendFilter = CIFilter(name: "CIBlendWithAlphaMask") else { return image }
        let transparent = CIImage(color: .clear).cropped(to: extent)
        blendFilter.setValue(image, forKey: kCIInputImageKey)
        blendFilter.setValue(transparent, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(maskImage, forKey: kCIInputMaskImageKey)

        return blendFilter.outputImage ?? image
    }

    /// Returns cached mask or creates a new one. The mask is a white rounded
    /// rectangle — identical for every frame at the same size and corner radius.
    private func getOrCreateMask(extent: CGRect, cornerRadius: CGFloat, videoSize: CGSize) -> CIImage {
        let size = extent.size
        if let cached = cachedMaskImage,
           cachedMaskSize == size,
           cachedMaskRadius == cornerRadius {
            return cached
        }

        guard let cgContext = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width) * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return CIImage(color: .white).cropped(to: extent)
        }

        // Scale corner radius proportionally
        let scaleFactor = min(size.width, size.height) / min(videoSize.width, videoSize.height)
        let scaledRadius = min(cornerRadius * scaleFactor, min(size.width, size.height) / 2)

        cgContext.setFillColor(CGColor.white)
        let path = CGPath(
            roundedRect: CGRect(origin: .zero, size: size),
            cornerWidth: scaledRadius,
            cornerHeight: scaledRadius,
            transform: nil
        )
        cgContext.addPath(path)
        cgContext.fillPath()

        guard let maskCGImage = cgContext.makeImage() else {
            return CIImage(color: .white).cropped(to: extent)
        }

        let maskImage = CIImage(cgImage: maskCGImage)
        cachedMaskImage = maskImage
        cachedMaskSize = size
        cachedMaskRadius = cornerRadius
        return maskImage
    }

    // MARK: - Shadow (Cached Shape-Based)

    /// Returns cached shadow or creates one from the rounded rectangle shape.
    /// The shadow is derived from the video SHAPE (rounded rect silhouette),
    /// not the video content — so it's identical every frame and only computed once.
    private func getOrCreateShadow(instruction: BackgroundCompositionInstruction) -> CIImage {
        let shadowRadius = instruction.shadowIntensity * 40

        if let cached = cachedShadowImage,
           cachedShadowVideoSize == instruction.videoSize,
           cachedShadowPadding == instruction.padding,
           cachedShadowRadius == instruction.cornerRadius,
           cachedShadowIntensity == instruction.shadowIntensity {
            return cached
        }

        // Create an opaque rounded rectangle silhouette at the video position
        let videoRect = CGRect(
            x: instruction.padding,
            y: instruction.padding,
            width: instruction.videoSize.width,
            height: instruction.videoSize.height
        )

        // Clamp corner radius to half the video size (no scaling needed —
        // shadow is drawn directly at instruction.videoSize coordinates)
        let scaledRadius = instruction.cornerRadius > 0
            ? min(instruction.cornerRadius, min(instruction.videoSize.width, instruction.videoSize.height) / 2)
            : 0

        // Draw black rounded rect silhouette on transparent canvas
        let canvasSize = instruction.paddedSize
        guard let cgContext = CGContext(
            data: nil,
            width: Int(canvasSize.width),
            height: Int(canvasSize.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(canvasSize.width) * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return CIImage(color: .clear).cropped(to: CGRect(origin: .zero, size: canvasSize))
        }

        cgContext.clear(CGRect(origin: .zero, size: canvasSize))
        cgContext.setFillColor(CGColor.black)

        if scaledRadius > 0 {
            let path = CGPath(
                roundedRect: videoRect,
                cornerWidth: scaledRadius,
                cornerHeight: scaledRadius,
                transform: nil
            )
            cgContext.addPath(path)
        } else {
            cgContext.addRect(videoRect)
        }
        cgContext.fillPath()

        guard let silhouetteCGImage = cgContext.makeImage() else {
            return CIImage(color: .clear).cropped(to: CGRect(origin: .zero, size: canvasSize))
        }

        // Blur the silhouette to create shadow, then adjust opacity
        let silhouette = CIImage(cgImage: silhouetteCGImage)
        let blurredShadow = silhouette
            .applyingGaussianBlur(sigma: Double(shadowRadius))
            .cropped(to: CGRect(origin: .zero, size: canvasSize))

        let shadowWithOpacity = blurredShadow.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(instruction.shadowIntensity * 0.8)),
            ]
        )

        // Cache the shadow — it's static for all frames
        cachedShadowImage = shadowWithOpacity
        cachedShadowVideoSize = instruction.videoSize
        cachedShadowPadding = instruction.padding
        cachedShadowRadius = instruction.cornerRadius
        cachedShadowIntensity = instruction.shadowIntensity
        return shadowWithOpacity
    }

    // MARK: - Background Creation (Cached)

    /// Returns cached background or creates one. Gradient and solid color backgrounds
    /// are static — no need to recreate per frame.
    private func getOrCreateBackground(style: VideoBackgroundStyle, size: CGSize) -> CIImage {
        let styleID = style.cacheKey
        if let cached = cachedBackground,
           cachedBackgroundSize == size,
           cachedBackgroundStyleID == styleID {
            return cached
        }

        let background = createBackground(style: style, size: size)
        cachedBackground = background
        cachedBackgroundSize = size
        cachedBackgroundStyleID = styleID
        return background
    }

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
