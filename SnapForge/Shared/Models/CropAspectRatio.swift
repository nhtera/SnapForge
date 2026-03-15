import CoreGraphics

/// Aspect ratio options for the crop tool.
enum CropAspectRatio: String, CaseIterable, Identifiable {
  case free
  case ratio1x1
  case ratio4x3
  case ratio16x9
  case ratio3x2
  case ratio9x16

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .free: return "Free"
    case .ratio1x1: return "1:1"
    case .ratio4x3: return "4:3"
    case .ratio16x9: return "16:9"
    case .ratio3x2: return "3:2"
    case .ratio9x16: return "9:16"
    }
  }

  /// Target ratio (width / height)
  var ratio: CGFloat {
    switch self {
    case .free: return 0
    case .ratio1x1: return 1
    case .ratio4x3: return 4.0 / 3.0
    case .ratio16x9: return 16.0 / 9.0
    case .ratio3x2: return 3.0 / 2.0
    case .ratio9x16: return 9.0 / 16.0
    }
  }
}
