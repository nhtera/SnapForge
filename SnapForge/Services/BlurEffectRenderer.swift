import AppKit
import CoreGraphics
import CoreImage

/// Renders real pixelate and Gaussian blur effects.
/// Uses direct pixel sampling for pixelate (reliable coordinates) and CIGaussianBlur for blur.
struct BlurEffectRenderer {

  /// Default pixel block size for pixelate effect
  static let defaultPixelSize: CGFloat = 12

  /// Default Gaussian blur radius
  static let defaultGaussianRadius: Double = 20.0

  /// Shared GPU-backed CIContext for performance
  static let sharedCIContext: CIContext = {
    if let metalDevice = MTLCreateSystemDefaultDevice() {
      return CIContext(mtlDevice: metalDevice, options: [
        .cacheIntermediates: true,
        .priorityRequestLow: false,
      ])
    }
    return CIContext(options: [.cacheIntermediates: true])
  }()

  // MARK: - Core: Crop source image region

  /// Extract CGImage from source image at the specified region (in image coordinates, bottom-left origin)
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

    // Convert image coords (bottom-left origin) to CGImage coords (top-left origin)
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

  // MARK: - Pixelate (Direct pixel sampling — Snapzy approach)

  /// Draw pixelated region using direct pixel sampling.
  /// More reliable than CIPixellate for coordinate alignment.
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

    drawPixelated(
      croppedImage: croppedCG,
      in: context,
      destRect: clampedRegion,
      pixelSize: pixelSize
    )
  }

  /// Draw pixelated version by sampling pixel colors and filling blocks
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

    // Normalize pixel data through a bitmap context with known RGBA format
    // This handles BGRA, ARGB, premultiplied alpha, and other variants
    let bytesPerPixel = 4
    let bytesPerRow = imageWidth * bytesPerPixel
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

    guard let bitmapContext = CGContext(
      data: nil,
      width: imageWidth,
      height: imageHeight,
      bitsPerComponent: 8,
      bytesPerRow: bytesPerRow,
      space: colorSpace,
      bitmapInfo: bitmapInfo.rawValue
    ) else {
      drawFallback(in: context, region: destRect)
      return
    }

    // Draw source image into normalized context
    bitmapContext.draw(croppedImage, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

    guard let pixelData = bitmapContext.data else {
      drawFallback(in: context, region: destRect)
      return
    }
    let bytes = pixelData.assumingMemoryBound(to: UInt8.self)

    // Clip to destRect to prevent blocks from overflowing
    context.saveGState()
    context.clip(to: destRect)

    for row in 0..<rows {
      for col in 0..<cols {
        // Sample from center of each grid cell
        let sampleX = Int((CGFloat(col) + 0.5) / CGFloat(cols) * CGFloat(imageWidth))
        let sampleY = Int((CGFloat(row) + 0.5) / CGFloat(rows) * CGFloat(imageHeight))

        let clampedX = min(max(sampleX, 0), imageWidth - 1)
        let clampedY = min(max(sampleY, 0), imageHeight - 1)

        let offset = clampedY * bytesPerRow + clampedX * bytesPerPixel
        let r = CGFloat(bytes[offset]) / 255.0
        let g = CGFloat(bytes[offset + 1]) / 255.0
        let b = CGFloat(bytes[offset + 2]) / 255.0
        let a = bytesPerPixel >= 4 ? CGFloat(bytes[offset + 3]) / 255.0 : 1.0

        // Block position: flip Y for Core Graphics (bottom-left origin)
        let blockX = destRect.origin.x + CGFloat(col) * pixelSize
        let blockY = destRect.origin.y + destRect.height - CGFloat(row + 1) * pixelSize

        let blockRect = CGRect(x: blockX, y: blockY, width: pixelSize, height: pixelSize)

        context.setFillColor(red: r, green: g, blue: b, alpha: a)
        context.fill(blockRect)
      }
    }

    context.restoreGState()
  }

  // MARK: - Pixelate NSImage (for BlurCacheManager)

  static func pixelateRegion(
    sourceImage: NSImage,
    region: CGRect,
    pixelSize: CGFloat = defaultPixelSize
  ) -> NSImage? {
    guard let (croppedCG, clampedRegion) = cropSourceImage(sourceImage, region: region) else {
      return nil
    }

    let width = Int(ceil(clampedRegion.width))
    let height = Int(ceil(clampedRegion.height))
    guard width > 0, height > 0 else { return nil }

    let nsImage = NSImage(size: NSSize(width: width, height: height))
    nsImage.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else {
      nsImage.unlockFocus()
      return nil
    }

    let destRect = CGRect(x: 0, y: 0, width: width, height: height)
    drawPixelated(croppedImage: croppedCG, in: context, destRect: destRect, pixelSize: pixelSize)

    nsImage.unlockFocus()
    return nsImage
  }

  // MARK: - Gaussian Blur (CIGaussianBlur)

  /// Draw Gaussian blur region directly into a CGContext
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

  /// Create a Gaussian-blurred NSImage from a source image region
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

    let croppedOutput = outputImage.cropped(to: ciImage.extent)
    guard let resultCG = sharedCIContext.createCGImage(croppedOutput, from: ciImage.extent) else {
      return nil
    }

    let width = Int(ceil(clampedRegion.width))
    let height = Int(ceil(clampedRegion.height))
    return NSImage(cgImage: resultCG, size: NSSize(width: width, height: height))
  }

  // MARK: - Fallback

  /// Fallback when image sampling fails — semi-transparent overlay
  static func drawFallback(in context: CGContext, region: CGRect) {
    context.setFillColor(NSColor.gray.withAlphaComponent(0.7).cgColor)
    context.fill(region)
  }
}
