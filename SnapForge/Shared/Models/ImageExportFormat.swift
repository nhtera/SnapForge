import Foundation

/// Supported image export formats.
enum ImageExportFormat: String, CaseIterable, Identifiable {
    case png = "PNG"
    case jpg = "JPG"
    case webp = "WebP"
    case heic = "HEIC"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpg: return "jpg"
        case .webp: return "webp"
        case .heic: return "heic"
        }
    }
}
