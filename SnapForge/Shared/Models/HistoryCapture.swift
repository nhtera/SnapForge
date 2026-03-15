import Foundation

/// Model for a history entry.
struct HistoryCapture: Identifiable {
    let id = UUID()
    let filename: String
    let filePath: String
    let date: Date
    let fileSize: Int64
    let type: CaptureType

    /// Shortened display name: remove "SnapForge_" prefix
    var displayName: String {
        var name = filename
        if name.hasPrefix("SnapForge_") {
            name = String(name.dropFirst("SnapForge_".count))
        }
        if name.hasPrefix("Recording_") {
            name = String(name.dropFirst("Recording_".count))
        }
        return name
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    enum CaptureType: String {
        case screenshot, recording, gif

        var icon: String {
            switch self {
            case .screenshot: "photo"
            case .recording: "video"
            case .gif: "photo.stack"
            }
        }

        var label: String {
            switch self {
            case .screenshot: "IMG"
            case .recording: "MOV"
            case .gif: "GIF"
            }
        }
    }
}
