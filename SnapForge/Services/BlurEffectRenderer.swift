import AppKit
import CoreGraphics
import CoreImage

/// Renders real pixelate and Gaussian blur effects using CIFilter (GPU-accelerated).
/// Uses CIPixellate for mosaic and CIGaussianBlur for blur — format-agnostic, thread-safe.
struct BlurEffectRenderer {

    /// Default pixel block size for pixelate effect
    static let defaultPixelSize: CGFloat = 12

    /// Default Gaussian blur radius
    static let defaultGaussianRadius: Double = 20.0

    /// Shared GPU-backed CIContext for performance (reused across all operations)
    static let sharedCIContext: CIContext = {
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: metalDevice, options: [
                .cacheIntermediates: true,
                .priorityRequestLow: false
            ])
        }
        return CIContext(options: [.cacheIntermediates: true])
    }()

    // MARK: - Core: Crop source image region to CGImage

    /// Extract CGImage from source image at the specified region (in NSImage coordinates)
    private static func cropSourceImage(
        _ sourceImage: NSImage,
        region: CGRect
    ) -> (cgImage: CGImage, clampedRegion: CGRect)? {
        guard region.width > 0, region.height > 0 else { return nil }

        guard let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let imageBounds = CGRect(origin: .zero, size: sourceImage.size)
        let clampedRegion = region.intersection(imageBounds)
        guard !clampedRegion.isEmpty, clampedRegion.width > 0, clampedRegion.height > 0 else { return nil }

        let imageScale = CGFloat(cgImage.width) / sourceImage.size.width

        // Convert NSImage coords (bottom-up) to CGImage coords (top-down)
        let pixelRegion = CGRect(
            x: clampedRegion.origin.x * imageScale,
            y: (sourceImage.size.height - clampedRegion.origin.y - clampedRegion.height) * imageScale,
            width: clampedRegion.width * imageScale,
            height: clampedRegion.height * imageScale
        )

        let clampedPixelRegion = pixelRegion.intersection(
            CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        )
        guard !clampedPixelRegion.isEmpty else { return nil }

        guard let cropped = cgImage.cropping(to: clampedPixelRegion) else { return nil }
        return (cropped, clampedRegion)
    }

    // MARK: - Pixelate (CIPixellate — GPU-accelerated)

    /// Create a pixelated NSImage from a source image region using CIPixellate filter.
    /// Thread-safe, format-agnostic, works from any thread including SwiftUI Canvas.
    static func pixelateRegion(
        sourceImage: NSImage,
        region: CGRect,
        pixelSize: CGFloat = defaultPixelSize
    ) -> NSImage? {
        guard let (croppedCG, clampedRegion) = cropSourceImage(sourceImage, region: region) else {
            return nil
        }

        // Use CIPixellate filter (GPU-accelerated, handles all pixel formats correctly)
        let ciImage = CIImage(cgImage: croppedCG)
        let filter = CIFilter(name: "CIPixellate")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(pixelSize, forKey: kCIInputScaleKey)
        // Center the pixel grid
        filter?.setValue(CIVector(x: ciImage.extent.midX, y: ciImage.extent.midY), forKey: kCIInputCenterKey)

        guard let outputImage = filter?.outputImage else { return nil }

        // Crop to original extent (pixellate might shift edges)
        let croppedOutput = outputImage.cropped(to: ciImage.extent)

        guard let resultCG = sharedCIContext.createCGImage(croppedOutput, from: ciImage.extent) else {
            return nil
        }

        let width = Int(ceil(clampedRegion.width))
        let height = Int(ceil(clampedRegion.height))
        return NSImage(cgImage: resultCG, size: NSSize(width: width, height: height))
    }

    /// Draw pixelated region directly into a CGContext (for ExportService)
    static func drawPixelatedRegion(
        in context: CGContext,
        sourceImage: NSImage,
        region: CGRect,
        pixelSize: CGFloat = defaultPixelSize
    ) {
        guard let (croppedCG, clampedRegion) = cropSourceImage(sourceImage, region: region) else {
            drawFallback(in: context, region: region)
            return
        }

        let ciImage = CIImage(cgImage: croppedCG)
        let filter = CIFilter(name: "CIPixellate")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(pixelSize, forKey: kCIInputScaleKey)
        filter?.setValue(CIVector(x: ciImage.extent.midX, y: ciImage.extent.midY), forKey: kCIInputCenterKey)

        guard let outputImage = filter?.outputImage else {
            drawFallback(in: context, region: region)
            return
        }

        let croppedOutput = outputImage.cropped(to: ciImage.extent)
        guard let resultCG = sharedCIContext.createCGImage(croppedOutput, from: ciImage.extent) else {
            drawFallback(in: context, region: region)
            return
        }

        context.draw(resultCG, in: clampedRegion)
    }

    // MARK: - Gaussian Blur (CIGaussianBlur — GPU-accelerated)

    /// Create a Gaussian-blurred NSImage from a source image region.
    /// Thread-safe, uses CIFilter GPU acceleration.
    static func blurRegion(
        sourceImage: NSImage,
        region: CGRect,
        radius: Double = defaultGaussianRadius
    ) -> NSImage? {
        guard let (croppedCG, clampedRegion) = cropSourceImage(sourceImage, region: region) else {
            return nil
        }

        let ciImage = CIImage(cgImage: croppedCG)
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(radius, forKey: kCIInputRadiusKey)

        guard let outputImage = filter?.outputImage else { return nil }

        // Crop to original extent (blur expands the image)
        let croppedOutput = outputImage.cropped(to: ciImage.extent)
        guard let resultCG = sharedCIContext.createCGImage(croppedOutput, from: ciImage.extent) else {
            return nil
        }

        let width = Int(ceil(clampedRegion.width))
        let height = Int(ceil(clampedRegion.height))
        return NSImage(cgImage: resultCG, size: NSSize(width: width, height: height))
    }

    /// Draw Gaussian blur region directly into a CGContext (for ExportService)
    static func drawGaussianRegion(
        in context: CGContext,
        sourceImage: NSImage,
        region: CGRect,
        radius: Double = defaultGaussianRadius
    ) {
        guard let (croppedCG, clampedRegion) = cropSourceImage(sourceImage, region: region) else {
            drawFallback(in: context, region: region)
            return
        }

        let ciImage = CIImage(cgImage: croppedCG)
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(radius, forKey: kCIInputRadiusKey)

        guard let outputImage = filter?.outputImage else {
            drawFallback(in: context, region: region)
            return
        }

        let croppedOutput = outputImage.cropped(to: ciImage.extent)
        guard let resultCG = sharedCIContext.createCGImage(croppedOutput, from: ciImage.extent) else {
            drawFallback(in: context, region: region)
            return
        }

        context.draw(resultCG, in: clampedRegion)
    }

    // MARK: - Fallback

    /// Fallback when image sampling fails — semi-transparent overlay
    static func drawFallback(in context: CGContext, region: CGRect) {
        context.setFillColor(NSColor.gray.withAlphaComponent(0.7).cgColor)
        context.fill(region)
    }
}
