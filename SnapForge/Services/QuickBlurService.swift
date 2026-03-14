import AppKit
import Vision

/// Service to auto-detect and blur sensitive content in screenshots.
/// Uses Vision framework to find text regions and faces, then applies blur.
@MainActor
final class QuickBlurService {
  static let shared = QuickBlurService()
  private init() {}

  /// Detect sensitive regions (text and faces) in an image and blur them.
  /// Returns a new image with blurred regions, or the original if nothing detected.
  func autoBlurSensitiveAreas(in image: NSImage) async -> NSImage {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      return image
    }

    let imageSize = image.size
    var regions: [CGRect] = []

    // Detect text regions
    let textRegions = await detectTextRegions(in: cgImage, imageSize: imageSize)
    regions.append(contentsOf: textRegions)

    // Detect face regions
    let faceRegions = await detectFaceRegions(in: cgImage, imageSize: imageSize)
    regions.append(contentsOf: faceRegions)

    guard !regions.isEmpty else { return image }

    // Merge overlapping regions for cleaner blur
    let mergedRegions = mergeOverlappingRects(regions, padding: 4)

    // Apply pixelated blur to each region
    return renderBlurred(image: image, regions: mergedRegions)
  }

  // MARK: - Detection

  private func detectTextRegions(
    in cgImage: CGImage, imageSize: NSSize
  ) async -> [CGRect] {
    await withCheckedContinuation { continuation in
      let request = VNRecognizeTextRequest { request, _ in
        guard let observations = request.results as? [VNRecognizedTextObservation] else {
          continuation.resume(returning: [])
          return
        }

        let rects = observations.map { observation -> CGRect in
          let box = observation.boundingBox
          // Vision uses normalized coordinates with bottom-left origin
          return CGRect(
            x: box.origin.x * imageSize.width,
            y: (1 - box.origin.y - box.height) * imageSize.height,
            width: box.width * imageSize.width,
            height: box.height * imageSize.height
          )
        }
        continuation.resume(returning: rects)
      }
      request.recognitionLevel = .fast
      request.recognitionLanguages = ["en", "vi"]

      let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
      do {
        try handler.perform([request])
      } catch {
        continuation.resume(returning: [])
      }
    }
  }

  private func detectFaceRegions(
    in cgImage: CGImage, imageSize: NSSize
  ) async -> [CGRect] {
    await withCheckedContinuation { continuation in
      let request = VNDetectFaceRectanglesRequest { request, _ in
        guard let observations = request.results as? [VNFaceObservation] else {
          continuation.resume(returning: [])
          return
        }

        let rects = observations.map { observation -> CGRect in
          let box = observation.boundingBox
          return CGRect(
            x: box.origin.x * imageSize.width,
            y: (1 - box.origin.y - box.height) * imageSize.height,
            width: box.width * imageSize.width,
            height: box.height * imageSize.height
          )
        }
        continuation.resume(returning: rects)
      }

      let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
      do {
        try handler.perform([request])
      } catch {
        continuation.resume(returning: [])
      }
    }
  }

  // MARK: - Rendering

  private func renderBlurred(image: NSImage, regions: [CGRect]) -> NSImage {
    let size = image.size
    let result = NSImage(size: size)
    result.lockFocus()

    // Draw original
    image.draw(in: NSRect(origin: .zero, size: size))

    // Create pixelated version using CIFilter
    guard let ciImage = CIImage(data: image.tiffRepresentation ?? Data()) else {
      result.unlockFocus()
      return image
    }

    let pixellateFilter = CIFilter(name: "CIPixellate")
    pixellateFilter?.setValue(ciImage, forKey: kCIInputImageKey)
    pixellateFilter?.setValue(max(size.width, size.height) / 40, forKey: kCIInputScaleKey)

    guard let outputImage = pixellateFilter?.outputImage else {
      result.unlockFocus()
      return image
    }

    let context = CIContext()
    guard let cgBlurred = context.createCGImage(outputImage, from: outputImage.extent) else {
      result.unlockFocus()
      return image
    }

    let blurredNSImage = NSImage(cgImage: cgBlurred, size: size)

    // Draw blurred regions on top
    for region in regions {
      let paddedRegion = region.insetBy(dx: -4, dy: -4)
      let clippedRegion = paddedRegion.intersection(NSRect(origin: .zero, size: size))

      NSGraphicsContext.current?.saveGraphicsState()
      NSBezierPath(roundedRect: clippedRegion, xRadius: 4, yRadius: 4).addClip()
      blurredNSImage.draw(in: NSRect(origin: .zero, size: size))
      NSGraphicsContext.current?.restoreGraphicsState()
    }

    result.unlockFocus()
    return result
  }

  // MARK: - Geometry Helpers

  /// Merge overlapping rectangles to reduce visual noise
  private func mergeOverlappingRects(_ rects: [CGRect], padding: CGFloat) -> [CGRect] {
    guard !rects.isEmpty else { return [] }

    var merged = rects.map { $0.insetBy(dx: -padding, dy: -padding) }
    var changed = true

    while changed {
      changed = false
      var result: [CGRect] = []

      while !merged.isEmpty {
        var current = merged.removeFirst()
        var i = 0

        while i < merged.count {
          if current.intersects(merged[i]) {
            current = current.union(merged[i])
            merged.remove(at: i)
            changed = true
          } else {
            i += 1
          }
        }
        result.append(current)
      }
      merged = result
    }

    return merged
  }
}
