import Foundation

/// Supported video export formats.
enum VideoExportFormat: String, CaseIterable, Identifiable {
    case mp4 = "MP4"
    case gif = "GIF"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .mp4: return "mp4"
        case .gif: return "gif"
        }
    }
}
