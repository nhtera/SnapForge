import Foundation

/// Common size presets for recording region
enum RecordingSizePreset: String, CaseIterable, Identifiable {
    case p1080, p720, square1080, p600, custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .p1080: return "1920 × 1080"
        case .p720: return "1280 × 720"
        case .square1080: return "1080 × 1080"
        case .p600: return "800 × 600"
        case .custom: return "Custom"
        }
    }

    var size: CGSize? {
        switch self {
        case .p1080: return CGSize(width: 1920, height: 1080)
        case .p720: return CGSize(width: 1280, height: 720)
        case .square1080: return CGSize(width: 1080, height: 1080)
        case .p600: return CGSize(width: 800, height: 600)
        case .custom: return nil
        }
    }
}
