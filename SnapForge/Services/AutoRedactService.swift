import AppKit
import Vision

/// Detected region that should be redacted, with type label.
struct RedactRegion: Identifiable, Equatable {
  let id = UUID()
  let bounds: CGRect
  let type: RedactType
  var isSelected: Bool = true

  static func == (lhs: RedactRegion, rhs: RedactRegion) -> Bool {
    lhs.id == rhs.id
  }
}

/// Category of sensitive content detected.
enum RedactType: String, CaseIterable {
  case face
  case email
  case phone
  case password
  case creditCard
  case ssn
  case ipAddress

  var displayName: String {
    switch self {
    case .face: "Face"
    case .email: "Email"
    case .phone: "Phone"
    case .password: "Password"
    case .creditCard: "Card Number"
    case .ssn: "SSN"
    case .ipAddress: "IP Address"
    }
  }

  var icon: String {
    switch self {
    case .face: "person.crop.circle"
    case .email: "envelope"
    case .phone: "phone"
    case .password: "key"
    case .creditCard: "creditcard"
    case .ssn: "number"
    case .ipAddress: "network"
    }
  }

  var color: NSColor {
    switch self {
    case .face: .systemPurple
    case .email: .systemBlue
    case .phone: .systemGreen
    case .password: .systemRed
    case .creditCard: .systemOrange
    case .ssn: .systemPink
    case .ipAddress: .systemTeal
    }
  }
}

/// Service that detects sensitive content in images using Vision framework.
/// Returns reviewable regions the user can select before applying redaction.
final class AutoRedactService: Sendable {
  static let shared = AutoRedactService()
  private init() {}

  /// Detect all sensitive regions in an image (runs on background thread).
  func detectSensitiveRegions(in image: NSImage) async -> [RedactRegion] {
    guard let tiffData = image.tiffRepresentation,
      let bitmapRep = NSBitmapImageRep(data: tiffData),
      let cgImage = bitmapRep.cgImage
    else {
      return []
    }

    let width = image.size.width
    let height = image.size.height

    // Detached to avoid blocking @MainActor with CPU-intensive Vision detection
    return await Task.detached(priority: .userInitiated) {
      var regions: [RedactRegion] = []

      // Detect faces
      let faceRects = Self.detectFaces(in: cgImage, width: width, height: height)
      regions.append(contentsOf: faceRects.map { RedactRegion(bounds: $0, type: .face) })

      // Detect sensitive text
      let textRegions = Self.detectSensitiveText(in: cgImage, width: width, height: height)
      regions.append(contentsOf: textRegions)

      return regions
    }.value
  }

  // MARK: - Face Detection

  private static func detectFaces(
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
    do {
      try handler.perform([request])
    } catch {
      print("❌ AutoRedactService: Face detection failed: \(error)")
    }
    return rects
  }

  // MARK: - Sensitive Text Detection

  private static func detectSensitiveText(
    in cgImage: CGImage, width: CGFloat, height: CGFloat
  ) -> [RedactRegion] {
    var regions: [RedactRegion] = []
    let request = VNRecognizeTextRequest { request, _ in
      guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
      for observation in observations {
        guard let candidate = observation.topCandidates(1).first else { continue }
        let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let sensitiveType = classifySensitiveText(text) else { continue }

        let box = observation.boundingBox
        let rect = CGRect(
          x: box.origin.x * width,
          y: (1 - box.origin.y - box.height) * height,
          width: box.width * width,
          height: box.height * height
        )
        regions.append(RedactRegion(bounds: rect, type: sensitiveType))
      }
    }
    request.recognitionLevel = .accurate
    request.recognitionLanguages = [
      "en-US", "fr-FR", "it-IT", "de-DE", "es-ES", "pt-BR",
      "zh-Hans", "zh-Hant", "ko-KR", "ja-JP",
      "ru-RU", "uk-UA", "th-TH", "vi-VN", "ar-SA",
    ]
    request.automaticallyDetectsLanguage = true

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
      try handler.perform([request])
    } catch {
      print("❌ AutoRedactService: Text detection failed: \(error)")
    }
    return regions
  }

  /// Classify text into a sensitive type, or nil if not sensitive.
  static func classifySensitiveText(_ text: String) -> RedactType? {
    guard text.count >= 3 else { return nil }

    // Email — use a proper regex to avoid false positives on @MainActor, variable names, etc.
    let emailPattern = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
    if text.range(of: emailPattern, options: .regularExpression) != nil { return .email }

    let digitsOnly = text.filter(\.isNumber)

    // SSN — must check before generic phone pattern
    let ssnPattern = #"^\d{3}[-\s]?\d{2}[-\s]?\d{4}$"#
    if text.range(of: ssnPattern, options: .regularExpression) != nil { return .ssn }

    // IP address — must check before generic phone pattern
    let ipPattern = #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"#
    if text.range(of: ipPattern, options: .regularExpression) != nil { return .ipAddress }

    // Credit card — must check before generic phone pattern
    if digitsOnly.count >= 13 && digitsOnly.count <= 19 {
      let ccChars = CharacterSet(charactersIn: "0123456789- ")
      if text.unicodeScalars.allSatisfy({ ccChars.contains($0) }) { return .creditCard }
    }

    // Phone (generic digit-based heuristic — checked last among digit patterns)
    if digitsOnly.count >= 7 && digitsOnly.count <= 15 {
      let phoneChars = CharacterSet(charactersIn: "0123456789+-() ")
      if text.unicodeScalars.allSatisfy({ phoneChars.contains($0) }) { return .phone }
    }

    // Password / token
    if looksLikePassword(text) { return .password }

    return nil
  }

  private static func looksLikePassword(_ text: String) -> Bool {
    guard text.count >= 6, !text.contains(" ") else { return false }

    let hasUpper = text.contains(where: \.isUppercase)
    let hasLower = text.contains(where: \.isLowercase)
    let hasDigit = text.contains(where: \.isNumber)
    let hasSpecial = text.contains(where: { !$0.isLetter && !$0.isNumber })

    let complexity = [hasUpper, hasLower, hasDigit, hasSpecial].filter { $0 }.count
    if complexity >= 3 { return true }

    let digitRatio = Double(text.filter(\.isNumber).count) / Double(text.count)
    if hasLower && hasDigit && digitRatio > 0.3 && text.count >= 8 { return true }

    return false
  }
}
