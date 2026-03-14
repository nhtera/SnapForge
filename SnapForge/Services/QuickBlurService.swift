import AppKit
import Vision

/// Service to auto-detect and blur sensitive content in screenshots.
/// Uses Vision framework to find text regions and faces, then applies blur.
/// All heavy work runs on a background thread to keep UI responsive.
final class QuickBlurService: Sendable {
  static let shared = QuickBlurService()
  private init() {}

  /// Detect sensitive regions (text and faces) in an image and blur them.
  /// Returns a new image with blurred regions, or the original if nothing detected.
  /// Safe to call from any thread — internally dispatches to background.
  func autoBlurSensitiveAreas(in image: NSImage) async -> NSImage {
    // Capture image data on caller's thread, then do all work in background
    guard let tiffData = image.tiffRepresentation,
          let bitmapRep = NSBitmapImageRep(data: tiffData),
          let cgImage = bitmapRep.cgImage else {
      return image
    }

    let imageWidth = image.size.width
    let imageHeight = image.size.height

    // Run entire pipeline (detection + rendering) off main thread
    let resultData: Data? = await Task.detached(priority: .userInitiated) {
      var regions: [CGRect] = []

      // Detect text regions
      let textRegions = Self.detectTextRegions(in: cgImage, width: imageWidth, height: imageHeight)
      regions.append(contentsOf: textRegions)

      // Detect face regions
      let faceRegions = Self.detectFaceRegions(in: cgImage, width: imageWidth, height: imageHeight)
      regions.append(contentsOf: faceRegions)

      guard !regions.isEmpty else { return nil as Data? }

      // Merge overlapping regions
      let mergedRegions = Self.mergeOverlappingRects(regions, padding: 4)

      // Render blurred result and return as TIFF data (thread-safe)
      return Self.renderBlurred(
        tiffData: tiffData, regions: mergedRegions,
        width: imageWidth, height: imageHeight
      )
    }.value

    // Convert result data back to NSImage on main thread
    if let resultData, let result = NSImage(data: resultData) {
      return result
    }
    return image
  }

  // MARK: - Detection (static, runs on background thread)

  private static func detectTextRegions(
    in cgImage: CGImage, width: CGFloat, height: CGFloat
  ) -> [CGRect] {
    var rects: [CGRect] = []
    let request = VNRecognizeTextRequest { request, _ in
      guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
      rects = observations.map { observation in
        let box = observation.boundingBox
        return CGRect(
          x: box.origin.x * width,
          y: (1 - box.origin.y - box.height) * height,
          width: box.width * width,
          height: box.height * height
        )
      }
    }
    request.recognitionLevel = .fast
    request.recognitionLanguages = ["en", "vi"]

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try? handler.perform([request])
    return rects
  }

  private static func detectFaceRegions(
    in cgImage: CGImage, width: CGFloat, height: CGFloat
  ) -> [CGRect] {
    var rects: [CGRect] = []
    let request = VNDetectFaceRectanglesRequest { request, _ in
      guard let observations = request.results as? [VNFaceObservation] else { return }
      rects = observations.map { observation in
        let box = observation.boundingBox
        return CGRect(
          x: box.origin.x * width,
          y: (1 - box.origin.y - box.height) * height,
          width: box.width * width,
          height: box.height * height
        )
      }
    }

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try? handler.perform([request])
    return rects
  }

  // MARK: - Rendering (static, uses CG-level APIs only — no lockFocus)

  private static func renderBlurred(
    tiffData: Data, regions: [CGRect],
    width: CGFloat, height: CGFloat
  ) -> Data? {
    guard let ciImage = CIImage(data: tiffData) else { return nil }

    // Create pixelated version
    let pixellateFilter = CIFilter(name: "CIPixellate")
    pixellateFilter?.setValue(ciImage, forKey: kCIInputImageKey)
    pixellateFilter?.setValue(max(width, height) / 40, forKey: kCIInputScaleKey)

    guard let pixelatedOutput = pixellateFilter?.outputImage else { return nil }

    // Composite: draw pixelated regions on top of original
    var composite = ciImage
    for region in regions {
      let paddedRegion = region.insetBy(dx: -4, dy: -4)
      let clippedRegion = paddedRegion.intersection(
        CGRect(x: 0, y: 0, width: width, height: height)
      )
      guard !clippedRegion.isEmpty else { continue }

      // Flip Y for CIImage (bottom-left origin)
      let ciRect = CGRect(
        x: clippedRegion.origin.x,
        y: height - clippedRegion.origin.y - clippedRegion.height,
        width: clippedRegion.width,
        height: clippedRegion.height
      )

      // Crop the pixelated region
      let croppedBlur = pixelatedOutput.cropped(to: ciRect)

      // Composite over the original
      composite = croppedBlur.composited(over: composite)
    }

    // Render final image to TIFF data
    let context = CIContext()
    guard let cgResult = context.createCGImage(composite, from: composite.extent) else {
      return nil
    }

    let rep = NSBitmapImageRep(cgImage: cgResult)
    return rep.tiffRepresentation
  }

  // MARK: - Geometry Helpers

  private static func mergeOverlappingRects(_ rects: [CGRect], padding: CGFloat) -> [CGRect] {
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
