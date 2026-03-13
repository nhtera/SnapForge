import AppKit
import CoreGraphics
import CoreImage

/// Renders real pixelate and Gaussian blur effects by sampling source image pixels.
/// Inspired by CleanShot X / Snapzy approach.
struct BlurEffectRenderer {

    /// Default pixel block size for pixelate effect
    static let defaultPixelSize: CGFloat = 12

    /// Default Gaussian blur radius
    static let defaultGaussianRadius: Double = 20.0

    /// Shared GPU-backed CIContext for blur performance
    static let sharedCIContext: CIContext = {
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: metalDevice, options: [
                .cacheIntermediates: true,
                .priorityRequestLow: false
            ])
        }
        return CIContext(options: [.cacheIntermediates: true])
    }()

    // MARK: - Pixelate

    /// Draw a pixelated version of the source image region
    /// - Parameters:
    ///   - context: CGContext to draw into
    ///   - sourceImage: The full source image
    ///   - region: Region in image coordinates to pixelate
    ///   - pixelSize: Size of each mosaic block (larger = more pixelated)
    static func drawPixelatedRegion(
        in context: CGContext,
        sourceImage: NSImage,
        region: CGRect,
        pixelSize: CGFloat = defaultPixelSize
    ) {
        guard region.width > 0, region.height > 0 else { return }

        guard let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            drawFallback(in: context, region: region)
            return
        }

        let imageBounds = CGRect(origin: .zero, size: sourceImage.size)
        let clampedRegion = region.intersection(imageBounds)
        guard !clampedRegion.isEmpty else {
            drawFallback(in: context, region: region)
            return
        }

        let imageScale = CGFloat(cgImage.width) / sourceImage.size.width

        // Convert to CGImage pixel coordinates (flip Y)
        let pixelRegion = CGRect(
            x: clampedRegion.origin.x * imageScale,
            y: (sourceImage.size.height - clampedRegion.origin.y - clampedRegion.height) * imageScale,
            width: clampedRegion.width * imageScale,
            height: clampedRegion.height * imageScale
        )

        let clampedPixelRegion = pixelRegion.intersection(
            CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        )
        guard !clampedPixelRegion.isEmpty else {
            drawFallback(in: context, region: region)
            return
        }

        guard let croppedImage = cgImage.cropping(to: clampedPixelRegion) else {
            drawFallback(in: context, region: region)
            return
        }

        drawPixelated(croppedImage: croppedImage, in: context, destRect: clampedRegion, pixelSize: pixelSize)
    }

    /// Draw a pixelated mosaic by sampling actual pixel colors
    private static func drawPixelated(
        croppedImage: CGImage,
        in context: CGContext,
        destRect: CGRect,
        pixelSize: CGFloat
    ) {
        let cols = Int(ceil(destRect.width / pixelSize))
        let rows = Int(ceil(destRect.height / pixelSize))
        guard cols > 0, rows > 0 else { return }

        let imageWidth = croppedImage.width
        let imageHeight = croppedImage.height

        guard let dataProvider = croppedImage.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else {
            drawFallback(in: context, region: destRect)
            return
        }

        let bytesPerPixel = croppedImage.bitsPerPixel / 8
        let bytesPerRow = croppedImage.bytesPerRow

        context.saveGState()
        context.clip(to: destRect)

        for row in 0..<rows {
            for col in 0..<cols {
                // Sample center of each block in image space
                let sampleX = min(max(Int((CGFloat(col) + 0.5) / CGFloat(cols) * CGFloat(imageWidth)), 0), imageWidth - 1)
                let sampleY = min(max(Int((CGFloat(row) + 0.5) / CGFloat(rows) * CGFloat(imageHeight)), 0), imageHeight - 1)

                let offset = sampleY * bytesPerRow + sampleX * bytesPerPixel
                let r = CGFloat(bytes[offset]) / 255.0
                let g = CGFloat(bytes[offset + 1]) / 255.0
                let b = CGFloat(bytes[offset + 2]) / 255.0
                let a = bytesPerPixel >= 4 ? CGFloat(bytes[offset + 3]) / 255.0 : 1.0

                // Block position (flip Y for Core Graphics)
                let blockX = destRect.origin.x + CGFloat(col) * pixelSize
                let blockY = destRect.origin.y + destRect.height - CGFloat(row + 1) * pixelSize
                let blockRect = CGRect(x: blockX, y: blockY, width: pixelSize, height: pixelSize)

                context.setFillColor(red: r, green: g, blue: b, alpha: a)
                context.fill(blockRect)
            }
        }

        context.restoreGState()
    }

    // MARK: - Gaussian Blur

    /// Draw a Gaussian-blurred version of the source image region
    static func drawGaussianRegion(
        in context: CGContext,
        sourceImage: NSImage,
        region: CGRect,
        radius: Double = defaultGaussianRadius
    ) {
        guard region.width > 0, region.height > 0 else { return }

        guard let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            drawFallback(in: context, region: region)
            return
        }

        let imageBounds = CGRect(origin: .zero, size: sourceImage.size)
        let clampedRegion = region.intersection(imageBounds)
        guard !clampedRegion.isEmpty else {
            drawFallback(in: context, region: region)
            return
        }

        let imageScale = CGFloat(cgImage.width) / sourceImage.size.width

        let pixelRegion = CGRect(
            x: clampedRegion.origin.x * imageScale,
            y: (sourceImage.size.height - clampedRegion.origin.y - clampedRegion.height) * imageScale,
            width: clampedRegion.width * imageScale,
            height: clampedRegion.height * imageScale
        )

        let clampedPixelRegion = pixelRegion.intersection(
            CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        )
        guard !clampedPixelRegion.isEmpty else {
            drawFallback(in: context, region: region)
            return
        }

        guard let croppedImage = cgImage.cropping(to: clampedPixelRegion) else {
            drawFallback(in: context, region: region)
            return
        }

        // Apply CIGaussianBlur
        let ciImage = CIImage(cgImage: croppedImage)
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(radius, forKey: kCIInputRadiusKey)

        guard let outputImage = filter?.outputImage else {
            drawFallback(in: context, region: region)
            return
        }

        // Crop to original extent (blur expands the image)
        let croppedOutput = outputImage.cropped(to: ciImage.extent)

        guard let blurredCGImage = sharedCIContext.createCGImage(croppedOutput, from: ciImage.extent) else {
            drawFallback(in: context, region: region)
            return
        }

        context.draw(blurredCGImage, in: clampedRegion)
    }

    // MARK: - Fallback

    /// Fallback when image sampling fails — semi-transparent overlay
    static func drawFallback(in context: CGContext, region: CGRect) {
        context.setFillColor(NSColor.gray.withAlphaComponent(0.7).cgColor)
        context.fill(region)
    }

    // MARK: - NSImage convenience

    /// Create a pixelated NSImage from a source image region
    static func pixelateRegion(
        sourceImage: NSImage,
        region: CGRect,
        pixelSize: CGFloat = defaultPixelSize
    ) -> NSImage? {
        let width = Int(ceil(region.width))
        let height = Int(ceil(region.height))
        guard width > 0, height > 0 else { return nil }

        let result = NSImage(size: NSSize(width: width, height: height))
        result.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            result.unlockFocus()
            return nil
        }

        drawPixelatedRegion(
            in: context,
            sourceImage: sourceImage,
            region: region,
            pixelSize: pixelSize
        )

        result.unlockFocus()
        return result
    }

    /// Create a Gaussian-blurred NSImage from a source image region
    static func blurRegion(
        sourceImage: NSImage,
        region: CGRect,
        radius: Double = defaultGaussianRadius
    ) -> NSImage? {
        let width = Int(ceil(region.width))
        let height = Int(ceil(region.height))
        guard width > 0, height > 0 else { return nil }

        let result = NSImage(size: NSSize(width: width, height: height))
        result.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            result.unlockFocus()
            return nil
        }

        drawGaussianRegion(
            in: context,
            sourceImage: sourceImage,
            region: region,
            radius: radius
        )

        result.unlockFocus()
        return result
    }
}
