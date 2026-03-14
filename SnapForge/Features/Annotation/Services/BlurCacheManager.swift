import AppKit
import CoreGraphics

/// Manages cached blur images for annotation items
/// Caches pixelated blur regions as CGImage to avoid per-frame recomputation
final class BlurCacheManager {
  private var cache: [UUID: CacheEntry] = [:]

  private struct CacheEntry {
    let image: CGImage
    let bounds: CGRect
    let blurType: BlurType
  }

  /// Get or create cached blur image for annotation
  func getCachedBlur(
    for annotationId: UUID,
    bounds: CGRect,
    sourceImage: NSImage,
    blurType: BlurType = .pixelated,
    pixelSize: CGFloat = BlurEffectRenderer.defaultPixelSize
  ) -> CGImage? {
    // Return cached if valid (same bounds and blur type)
    if let entry = cache[annotationId], entry.bounds == bounds, entry.blurType == blurType {
      return entry.image
    }

    // Render to offscreen context
    guard let rendered = renderBlurToImage(
      bounds: bounds,
      sourceImage: sourceImage,
      blurType: blurType,
      pixelSize: pixelSize
    ) else { return nil }

    cache[annotationId] = CacheEntry(image: rendered, bounds: bounds, blurType: blurType)
    return rendered
  }

  /// Invalidate cache for annotation (call on bounds change)
  func invalidate(id: UUID) {
    cache.removeValue(forKey: id)
  }

  /// Clear all cache (call on image change)
  func clearAll() {
    cache.removeAll()
  }

  /// Check if cache exists for annotation
  func hasCachedBlur(for annotationId: UUID) -> Bool {
    cache[annotationId] != nil
  }

  private func renderBlurToImage(
    bounds: CGRect,
    sourceImage: NSImage,
    blurType: BlurType,
    pixelSize: CGFloat
  ) -> CGImage? {
    let width = Int(ceil(bounds.width))
    let height = Int(ceil(bounds.height))
    guard width > 0, height > 0 else { return nil }

    guard let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    let localRegion = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)

    switch blurType {
    case .pixelated:
      renderPixelatedRegion(
        in: context,
        sourceImage: sourceImage,
        sourceRegion: bounds,
        destRegion: localRegion,
        pixelSize: pixelSize
      )
    case .gaussian:
      renderGaussianRegion(
        in: context,
        sourceImage: sourceImage,
        sourceRegion: bounds,
        destRegion: localRegion
      )
    }

    return context.makeImage()
  }

  /// Render pixelated region using CIPixellate filter
  private func renderPixelatedRegion(
    in context: CGContext,
    sourceImage: NSImage,
    sourceRegion: CGRect,
    destRegion: CGRect,
    pixelSize: CGFloat
  ) {
    guard sourceRegion.width > 0, sourceRegion.height > 0 else { return }

    guard let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      drawFallbackBlur(in: context, region: destRegion)
      return
    }

    let imageBounds = CGRect(origin: .zero, size: sourceImage.size)
    let clampedSourceRegion = sourceRegion.intersection(imageBounds)
    guard !clampedSourceRegion.isEmpty, clampedSourceRegion.width > 0, clampedSourceRegion.height > 0 else {
      drawFallbackBlur(in: context, region: destRegion)
      return
    }

    let clampedDestRegion: CGRect
    if clampedSourceRegion == sourceRegion {
      clampedDestRegion = destRegion
    } else {
      let offsetX = clampedSourceRegion.origin.x - sourceRegion.origin.x
      let offsetY = clampedSourceRegion.origin.y - sourceRegion.origin.y
      let scaleX = destRegion.width / sourceRegion.width
      let scaleY = destRegion.height / sourceRegion.height
      clampedDestRegion = CGRect(
        x: destRegion.origin.x + offsetX * scaleX,
        y: destRegion.origin.y + offsetY * scaleY,
        width: clampedSourceRegion.width * scaleX,
        height: clampedSourceRegion.height * scaleY
      )
    }

    let imageScale = CGFloat(cgImage.width) / sourceImage.size.width

    let pixelRegion = CGRect(
      x: clampedSourceRegion.origin.x * imageScale,
      y: (sourceImage.size.height - clampedSourceRegion.origin.y - clampedSourceRegion.height) * imageScale,
      width: clampedSourceRegion.width * imageScale,
      height: clampedSourceRegion.height * imageScale
    )

    let clampedPixelRegion = pixelRegion.intersection(
      CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
    )
    guard !clampedPixelRegion.isEmpty else {
      drawFallbackBlur(in: context, region: destRegion)
      return
    }

    guard let croppedImage = cgImage.cropping(to: clampedPixelRegion) else {
      drawFallbackBlur(in: context, region: destRegion)
      return
    }

    // Use CIPixellate for professional mosaic effect
    let ciImage = CIImage(cgImage: croppedImage)
    let filter = CIFilter(name: "CIPixellate")
    filter?.setValue(ciImage, forKey: kCIInputImageKey)
    filter?.setValue(pixelSize, forKey: kCIInputScaleKey)
    filter?.setValue(
      CIVector(x: ciImage.extent.midX, y: ciImage.extent.midY),
      forKey: kCIInputCenterKey
    )

    guard let outputImage = filter?.outputImage else {
      drawPixelated(croppedImage: croppedImage, in: context, destRect: clampedDestRegion, pixelSize: pixelSize)
      return
    }

    let croppedOutput = outputImage.cropped(to: ciImage.extent)
    guard let pixelatedCG = BlurEffectRenderer.sharedCIContext.createCGImage(croppedOutput, from: ciImage.extent) else {
      drawPixelated(croppedImage: croppedImage, in: context, destRect: clampedDestRegion, pixelSize: pixelSize)
      return
    }

    context.draw(pixelatedCG, in: clampedDestRegion)
  }

  /// Draw pixelated version of cropped image region
  private func drawPixelated(
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
      drawFallbackBlur(in: context, region: destRect)
      return
    }

    let bytesPerPixel = croppedImage.bitsPerPixel / 8
    let bytesPerRow = croppedImage.bytesPerRow

    context.saveGState()
    context.clip(to: destRect)

    for row in 0..<rows {
      for col in 0..<cols {
        let sampleX = Int((CGFloat(col) + 0.5) / CGFloat(cols) * CGFloat(imageWidth))
        let sampleY = Int((CGFloat(row) + 0.5) / CGFloat(rows) * CGFloat(imageHeight))

        let clampedX = min(max(sampleX, 0), imageWidth - 1)
        let clampedY = min(max(sampleY, 0), imageHeight - 1)

        let offset = clampedY * bytesPerRow + clampedX * bytesPerPixel
        let r = CGFloat(bytes[offset]) / 255.0
        let g = CGFloat(bytes[offset + 1]) / 255.0
        let b = CGFloat(bytes[offset + 2]) / 255.0
        let a = bytesPerPixel >= 4 ? CGFloat(bytes[offset + 3]) / 255.0 : 1.0

        let blockX = destRect.origin.x + CGFloat(col) * pixelSize
        let blockY = destRect.origin.y + destRect.height - CGFloat(row + 1) * pixelSize

        let blockRect = CGRect(x: blockX, y: blockY, width: pixelSize, height: pixelSize)

        context.setFillColor(red: r, green: g, blue: b, alpha: a)
        context.fill(blockRect)
      }
    }

    context.restoreGState()
  }

  private func drawFallbackBlur(in context: CGContext, region: CGRect) {
    context.setFillColor(NSColor.gray.withAlphaComponent(0.7).cgColor)
    context.fill(region)
  }

  /// Render Gaussian blur region using CIFilter (GPU-accelerated)
  private func renderGaussianRegion(
    in context: CGContext,
    sourceImage: NSImage,
    sourceRegion: CGRect,
    destRegion: CGRect
  ) {
    guard sourceRegion.width > 0, sourceRegion.height > 0 else { return }

    guard let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      drawFallbackBlur(in: context, region: destRegion)
      return
    }

    let imageBounds = CGRect(origin: .zero, size: sourceImage.size)
    let clampedSourceRegion = sourceRegion.intersection(imageBounds)
    guard !clampedSourceRegion.isEmpty, clampedSourceRegion.width > 0, clampedSourceRegion.height > 0 else {
      drawFallbackBlur(in: context, region: destRegion)
      return
    }

    let clampedDestRegion: CGRect
    if clampedSourceRegion == sourceRegion {
      clampedDestRegion = destRegion
    } else {
      let offsetX = clampedSourceRegion.origin.x - sourceRegion.origin.x
      let offsetY = clampedSourceRegion.origin.y - sourceRegion.origin.y
      let scaleX = destRegion.width / sourceRegion.width
      let scaleY = destRegion.height / sourceRegion.height
      clampedDestRegion = CGRect(
        x: destRegion.origin.x + offsetX * scaleX,
        y: destRegion.origin.y + offsetY * scaleY,
        width: clampedSourceRegion.width * scaleX,
        height: clampedSourceRegion.height * scaleY
      )
    }

    let imageScale = CGFloat(cgImage.width) / sourceImage.size.width

    let pixelRegion = CGRect(
      x: clampedSourceRegion.origin.x * imageScale,
      y: (sourceImage.size.height - clampedSourceRegion.origin.y - clampedSourceRegion.height) * imageScale,
      width: clampedSourceRegion.width * imageScale,
      height: clampedSourceRegion.height * imageScale
    )

    let clampedPixelRegion = pixelRegion.intersection(
      CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
    )
    guard !clampedPixelRegion.isEmpty else {
      drawFallbackBlur(in: context, region: destRegion)
      return
    }

    guard let croppedImage = cgImage.cropping(to: clampedPixelRegion) else {
      drawFallbackBlur(in: context, region: destRegion)
      return
    }

    let ciImage = CIImage(cgImage: croppedImage)
    let filter = CIFilter(name: "CIGaussianBlur")
    filter?.setValue(ciImage, forKey: kCIInputImageKey)
    filter?.setValue(BlurEffectRenderer.defaultGaussianRadius, forKey: kCIInputRadiusKey)

    guard let outputImage = filter?.outputImage else {
      drawFallbackBlur(in: context, region: destRegion)
      return
    }

    let ciContext = BlurEffectRenderer.sharedCIContext
    let croppedOutput = outputImage.cropped(to: ciImage.extent)

    guard let blurredCGImage = ciContext.createCGImage(croppedOutput, from: ciImage.extent) else {
      drawFallbackBlur(in: context, region: destRegion)
      return
    }

    context.draw(blurredCGImage, in: clampedDestRegion)
  }
}
