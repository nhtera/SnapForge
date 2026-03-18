import SwiftUI

/// Output mode for recording: video file or animated GIF
enum RecordingOutputMode: String, CaseIterable, Sendable {
    case video, gif

    var badgeColor: Color {
        self == .gif ? .orange : .blue
    }

    var displayName: String {
        self == .gif ? "GIF" : "Video"
    }
}
