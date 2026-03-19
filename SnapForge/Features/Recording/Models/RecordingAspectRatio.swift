import Foundation

/// Aspect ratio constraint options for recording region
enum RecordingAspectRatio: String, CaseIterable, Identifiable {
    case free, ratio16x9, ratio4x3, ratio1x1, ratio9x16

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .ratio16x9: return "16:9"
        case .ratio4x3: return "4:3"
        case .ratio1x1: return "1:1"
        case .ratio9x16: return "9:16"
        }
    }

    /// Width / Height ratio. nil = unconstrained.
    var value: CGFloat? {
        switch self {
        case .free: return nil
        case .ratio16x9: return 16.0 / 9.0
        case .ratio4x3: return 4.0 / 3.0
        case .ratio1x1: return 1.0
        case .ratio9x16: return 9.0 / 16.0
        }
    }
}
