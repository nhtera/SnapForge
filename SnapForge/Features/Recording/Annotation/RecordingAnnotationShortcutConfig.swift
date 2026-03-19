import AppKit

/// Modifier key options for activating annotation shortcut mode
enum AnnotationShortcutModifier: String, CaseIterable, Identifiable {
    case shift
    case control
    case option

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .shift: return "Shift (⇧)"
        case .control: return "Control (⌃)"
        case .option: return "Option (⌥)"
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .shift: return .shift
        case .control: return .control
        case .option: return .option
        }
    }
}

/// Persisted configuration for annotation shortcut activation (modifier key + hold duration)
@MainActor @Observable
final class RecordingAnnotationShortcutConfig {
    static let shared = RecordingAnnotationShortcutConfig()

    var modifier: AnnotationShortcutModifier {
        didSet { save() }
    }

    var holdDuration: TimeInterval {
        didSet { save() }
    }

    static let defaultModifier: AnnotationShortcutModifier = .shift
    static let defaultHoldDuration: TimeInterval = 0.3

    private init() {
        let storedModifier = UserDefaults.standard.string(forKey: SettingsKey.annotationShortcutModifier)
        self.modifier = storedModifier.flatMap { AnnotationShortcutModifier(rawValue: $0) }
            ?? Self.defaultModifier

        let storedDuration = UserDefaults.standard.double(forKey: SettingsKey.annotationShortcutHoldDuration)
        self.holdDuration = storedDuration > 0 ? storedDuration : Self.defaultHoldDuration
    }

    private func save() {
        UserDefaults.standard.set(modifier.rawValue, forKey: SettingsKey.annotationShortcutModifier)
        UserDefaults.standard.set(holdDuration, forKey: SettingsKey.annotationShortcutHoldDuration)
    }
}
