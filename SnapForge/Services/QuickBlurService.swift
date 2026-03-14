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
      for observation in observations {
        // Get the recognized text to check if it's sensitive
        guard let candidate = observation.topCandidates(1).first else { continue }
        let text = candidate.string

        // Only blur text that matches sensitive patterns
        guard isSensitiveText(text) else { continue }

        let box = observation.boundingBox
        rects.append(CGRect(
          x: box.origin.x * width,
          y: (1 - box.origin.y - box.height) * height,
          width: box.width * width,
          height: box.height * height
        ))
      }
    }
    request.recognitionLevel = .accurate  // Need accurate text to check patterns
    request.recognitionLanguages = ["en", "vi"]

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try? handler.perform([request])
    return rects
  }

  /// Check if text looks like sensitive content that should be auto-blurred
  private static func isSensitiveText(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count >= 3 else { return false }

    // Email pattern: contains @ with domain
    if trimmed.contains("@") && trimmed.contains(".") { return true }

    // Phone pattern: digits with dashes/spaces/parens, 7+ digits
    let digitsOnly = trimmed.filter(\.isNumber)
    if digitsOnly.count >= 7 && digitsOnly.count <= 15 {
      let phoneChars = CharacterSet(charactersIn: "0123456789+-() .")
      if trimmed.unicodeScalars.allSatisfy({ phoneChars.contains($0) }) { return true }
    }

    // SSN-like: ###-##-#### or similar
    let ssnPattern = #"^\d{3}[-\s]?\d{2}[-\s]?\d{4}$"#
    if trimmed.range(of: ssnPattern, options: .regularExpression) != nil { return true }

    // Credit card: 13-19 digits (with optional spaces/dashes)
    if digitsOnly.count >= 13 && digitsOnly.count <= 19 {
      let ccChars = CharacterSet(charactersIn: "0123456789- ")
      if trimmed.unicodeScalars.allSatisfy({ ccChars.contains($0) }) { return true }
    }

    // Password-like: random alphanumeric string (high entropy, mixed case/digits)
    if looksLikePassword(trimmed) { return true }

    // IP address
    let ipPattern = #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"#
    if trimmed.range(of: ipPattern, options: .regularExpression) != nil { return true }

    return false
  }

  /// Heuristic: string looks like a password or token (mixed case + digits, no spaces)
  private static func looksLikePassword(_ text: String) -> Bool {
    guard text.count >= 6, !text.contains(" ") else { return false }

    let hasUpper = text.contains(where: \.isUppercase)
    let hasLower = text.contains(where: \.isLowercase)
    let hasDigit = text.contains(where: \.isNumber)
    let hasSpecial = text.contains(where: { !$0.isLetter && !$0.isNumber })

    // Mixed case + digits = likely password/token
    let complexity = [hasUpper, hasLower, hasDigit, hasSpecial].filter { $0 }.count
    if complexity >= 3 { return true }

    // High ratio of digits in alphanumeric string = likely token
    let digitRatio = Double(text.filter(\.isNumber).count) / Double(text.count)
    if hasLower && hasDigit && digitRatio > 0.3 && text.count >= 8 { return true }

    return false
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

    // CIImage extent is in PIXELS, but detection regions are in POINTS
    let pixelWidth = ciImage.extent.width
    let pixelHeight = ciImage.extent.height
    let scaleX = pixelWidth / width
    let scaleY = pixelHeight / height

    // Create pixelated version (scale relative to pixel dimensions)
    let pixellateFilter = CIFilter(name: "CIPixellate")
    pixellateFilter?.setValue(ciImage, forKey: kCIInputImageKey)
    pixellateFilter?.setValue(max(pixelWidth, pixelHeight) / 40, forKey: kCIInputScaleKey)

    guard let pixelatedOutput = pixellateFilter?.outputImage else { return nil }

    // Composite: draw pixelated regions on top of original
    var composite = ciImage
    for region in regions {
      let paddedRegion = region.insetBy(dx: -4, dy: -4)
      let clippedRegion = paddedRegion.intersection(
        CGRect(x: 0, y: 0, width: width, height: height)
      )
      guard !clippedRegion.isEmpty else { continue }

      // Scale from points → pixels and flip Y for CIImage (bottom-left origin)
      let ciRect = CGRect(
        x: clippedRegion.origin.x * scaleX,
        y: (height - clippedRegion.origin.y - clippedRegion.height) * scaleY,
        width: clippedRegion.width * scaleX,
        height: clippedRegion.height * scaleY
      )

      // Crop the pixelated region and composite over original
      let croppedBlur = pixelatedOutput.cropped(to: ciRect)
      composite = croppedBlur.composited(over: composite)
    }

    // Render final image to TIFF data
    let context = CIContext()
    guard let cgResult = context.createCGImage(composite, from: composite.extent) else {
      return nil
    }

    let rep = NSBitmapImageRep(cgImage: cgResult)
    rep.size = NSSize(width: width, height: height)  // Preserve logical size
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
