import Foundation

/// Position options for keystroke overlay badge during recording
enum KeystrokeOverlayPosition: String, CaseIterable, Identifiable {
    case bottomCenter, bottomLeft, bottomRight
    case topCenter, topLeft, topRight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bottomCenter: return "Bottom Center"
        case .bottomLeft:   return "Bottom Left"
        case .bottomRight:  return "Bottom Right"
        case .topCenter:    return "Top Center"
        case .topLeft:      return "Top Left"
        case .topRight:     return "Top Right"
        }
    }
}

/// Configuration for keystroke overlay visualization during recording.
/// Reads from UserDefaults with sensible defaults matching existing hardcoded values.
struct KeystrokeOverlayConfiguration {
    let fontSize: CGFloat
    let position: KeystrokeOverlayPosition
    let displayDuration: Double

    init() {
        let ud = UserDefaults.standard
        let size = ud.object(forKey: SettingsKey.keystrokeFontSize) as? CGFloat
        fontSize = size ?? 22
        let raw = ud.string(forKey: SettingsKey.keystrokePosition)
        position = raw.flatMap(KeystrokeOverlayPosition.init(rawValue:)) ?? .bottomCenter
        let dur = ud.object(forKey: SettingsKey.keystrokeDisplayDuration) as? Double
        displayDuration = dur ?? 1.5
    }
}
