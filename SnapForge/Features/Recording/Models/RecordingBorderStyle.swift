import SwiftUI

/// Available border styles for the active recording area indicator
enum RecordingBorderStyle: String, CaseIterable, Identifiable {
    case solid, dashed, glow, none

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .solid:  return "Solid"
        case .dashed: return "Dashed"
        case .glow:   return "Glow"
        case .none:   return "None"
        }
    }
}

/// Configuration for recording border appearance.
/// Pre-record border is always accent+dashed; this config applies to active recording only.
struct RecordingBorderConfiguration {
    let style: RecordingBorderStyle
    let color: Color

    init() {
        let ud = UserDefaults.standard
        let raw = ud.string(forKey: SettingsKey.recordingBorderStyle) ?? "solid"
        style = RecordingBorderStyle(rawValue: raw) ?? .solid

        if let data = ud.data(forKey: SettingsKey.recordingBorderColor),
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            color = Color(nsColor: nsColor)
        } else {
            color = .red
        }
    }
}
