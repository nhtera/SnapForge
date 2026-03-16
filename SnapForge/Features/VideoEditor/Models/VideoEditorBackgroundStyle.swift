import SwiftUI

// MARK: - Video Background Style

/// Background style options for video export.
enum VideoBackgroundStyle: Equatable, Hashable {
    case none
    case gradient(VideoGradientPreset)
    case solidColor(Color)
    case wallpaper(URL)
}

// MARK: - Video Gradient Preset

/// Pre-defined gradient backgrounds for video export.
enum VideoGradientPreset: String, CaseIterable, Identifiable, Hashable {
    case sunset
    case ocean
    case forest
    case lavender
    case flame
    case midnight
    case peach
    case arctic

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }

    var colors: [Color] {
        switch self {
        case .sunset: [Color(red: 1.0, green: 0.4, blue: 0.3), Color(red: 1.0, green: 0.7, blue: 0.2)]
        case .ocean: [Color(red: 0.2, green: 0.4, blue: 0.9), Color(red: 0.3, green: 0.8, blue: 0.9)]
        case .forest: [Color(red: 0.2, green: 0.7, blue: 0.4), Color(red: 0.1, green: 0.4, blue: 0.3)]
        case .lavender: [Color(red: 0.6, green: 0.3, blue: 0.9), Color(red: 0.9, green: 0.5, blue: 0.8)]
        case .flame: [Color(red: 1.0, green: 0.5, blue: 0.0), Color(red: 1.0, green: 0.2, blue: 0.2)]
        case .midnight: [Color(red: 0.1, green: 0.1, blue: 0.3), Color(red: 0.3, green: 0.1, blue: 0.5)]
        case .peach: [Color(red: 1.0, green: 0.8, blue: 0.6), Color(red: 1.0, green: 0.6, blue: 0.5)]
        case .arctic: [Color(red: 0.8, green: 0.9, blue: 1.0), Color(red: 0.5, green: 0.7, blue: 0.9)]
        }
    }

    var gradient: LinearGradient {
        LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
