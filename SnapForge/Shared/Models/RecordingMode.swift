import Foundation

/// Defines recording modes.
enum RecordingMode: String, CaseIterable, Identifiable {
    case area = "Area"
    case window = "Window"
    case fullscreen = "Fullscreen"

    var id: String { rawValue }
}
