import AppKit

/// Configuration for click highlight visualization during recording.
/// Reads from UserDefaults with sensible defaults matching existing hardcoded values.
struct ClickHighlightConfiguration {
    let highlightSize: CGFloat
    let holdCircleSize: CGFloat
    let animationDuration: Double
    let rippleCount: Int
    let highlightColor: NSColor
    let highlightOpacity: Double

    init() {
        let ud = UserDefaults.standard
        let size = ud.object(forKey: SettingsKey.clickHighlightSize) as? CGFloat ?? 44
        highlightSize = size
        holdCircleSize = (size / 44) * 30
        animationDuration = ud.object(forKey: SettingsKey.clickHighlightAnimationDuration) as? Double ?? 0.5
        let count = ud.integer(forKey: SettingsKey.clickHighlightRippleCount)
        rippleCount = count > 0 ? count : 1
        highlightOpacity = ud.object(forKey: SettingsKey.clickHighlightOpacity) as? Double ?? 0.7

        if let data = ud.data(forKey: SettingsKey.clickHighlightColor),
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            highlightColor = color
        } else {
            highlightColor = .systemYellow
        }
    }
}
