import Foundation
import AppKit
import Carbon.HIToolbox

/// Manages global keyboard shortcuts using NSEvent monitors (sandbox-compatible).
/// Supports customizable hotkeys with persistence via UserDefaults.
@MainActor
@Observable
final class HotkeyService {

    struct Hotkey: Identifiable, Codable, Hashable {
        let id: String
        var keyCode: UInt16
        var modifiersRawValue: UInt64
        var label: String
        var description: String

        var modifiers: CGEventFlags {
            CGEventFlags(rawValue: modifiersRawValue)
        }

        /// Convert CGEventFlags to NSEvent.ModifierFlags for comparison
        var nsModifiers: NSEvent.ModifierFlags {
            var flags: NSEvent.ModifierFlags = []
            let cg = modifiers
            if cg.contains(.maskCommand) { flags.insert(.command) }
            if cg.contains(.maskShift) { flags.insert(.shift) }
            if cg.contains(.maskAlternate) { flags.insert(.option) }
            if cg.contains(.maskControl) { flags.insert(.control) }
            return flags
        }

        /// Whether this hotkey has no key assigned
        var isUnassigned: Bool {
            keyCode == 0 && modifiersRawValue == 0
        }

        init(id: String, keyCode: UInt16, modifiers: CGEventFlags, label: String, description: String = "") {
            self.id = id
            self.keyCode = keyCode
            self.modifiersRawValue = modifiers.rawValue
            self.label = label
            self.description = description
        }

        // MARK: - Default Hotkeys

        static let captureArea = Hotkey(
            id: "captureArea",
            keyCode: UInt16(kVK_ANSI_4),
            modifiers: [.maskCommand, .maskShift],
            label: "Capture Area",
            description: "Select a region to capture"
        )

        static let captureFullscreen = Hotkey(
            id: "captureFullscreen",
            keyCode: UInt16(kVK_ANSI_3),
            modifiers: [.maskCommand, .maskShift],
            label: "Capture Fullscreen",
            description: "Capture entire screen instantly"
        )

        static let captureWindow = Hotkey(
            id: "captureWindow",
            keyCode: UInt16(kVK_ANSI_W),
            modifiers: [.maskCommand, .maskShift],
            label: "Capture Window",
            description: "Capture a specific window"
        )

        static let selfTimer = Hotkey(
            id: "selfTimer",
            keyCode: UInt16(kVK_ANSI_T),
            modifiers: [.maskCommand, .maskShift],
            label: "Self-Timer",
            description: "Capture with a countdown delay"
        )

        static let startRecording = Hotkey(
            id: "startRecording",
            keyCode: UInt16(kVK_ANSI_5),
            modifiers: [.maskCommand, .maskShift],
            label: "Record / Stop",
            description: "Start or stop screen recording"
        )

        static let toggleOCR = Hotkey(
            id: "toggleOCR",
            keyCode: UInt16(kVK_ANSI_O),
            modifiers: [.maskCommand, .maskShift],
            label: "OCR Capture",
            description: "Extract text from screen region"
        )

        static let colorPicker = Hotkey(
            id: "colorPicker",
            keyCode: UInt16(kVK_ANSI_C),
            modifiers: [.maskCommand, .maskShift],
            label: "Color Picker",
            description: "Pick and copy any screen color"
        )

        static let scrollCapture = Hotkey(
            id: "scrollCapture",
            keyCode: UInt16(kVK_ANSI_S),
            modifiers: [.maskCommand, .maskShift],
            label: "Scroll Capture",
            description: "Capture scrollable content"
        )

        static let captureHistory = Hotkey(
            id: "captureHistory",
            keyCode: 0,
            modifiers: [],
            label: "Capture History",
            description: "Browse previous captures"
        )

        static let pinFromClipboard = Hotkey(
            id: "pinFromClipboard",
            keyCode: 0,
            modifiers: [],
            label: "Pin from Clipboard",
            description: "Pin clipboard image to screen"
        )
    }

    // MARK: - Default Set

    static let defaultHotkeys: [Hotkey] = [
        .captureArea,
        .captureFullscreen,
        .captureWindow,
        .selfTimer,
        .startRecording,
        .toggleOCR,
        .colorPicker,
        .scrollCapture,
        .captureHistory,
        .pinFromClipboard,
    ]

    // MARK: - State

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var hotkeyActions: [String: @Sendable () -> Void] = [:]

    var registeredHotkeys: [Hotkey] = defaultHotkeys

    var isListening = false

    // MARK: - Registration

    func register(hotkey: Hotkey, action: @escaping @Sendable () -> Void) {
        hotkeyActions[hotkey.id] = action
    }

    // MARK: - Persistence

    /// Load custom hotkey bindings from UserDefaults. Merges with defaults
    /// to ensure any newly-added hotkeys appear even if the user has saved data.
    func loadCustomHotkeys() {
        guard let data = UserDefaults.standard.data(forKey: SettingsKey.customHotkeysData) else {
            return
        }
        do {
            let saved = try JSONDecoder().decode([Hotkey].self, from: data)
            let savedById = Dictionary(uniqueKeysWithValues: saved.map { ($0.id, $0) })

            // Merge: use saved version if available, else keep default
            registeredHotkeys = Self.defaultHotkeys.map { defaultHotkey in
                if let saved = savedById[defaultHotkey.id] {
                    return Hotkey(
                        id: defaultHotkey.id,
                        keyCode: saved.keyCode,
                        modifiers: CGEventFlags(rawValue: saved.modifiersRawValue),
                        label: defaultHotkey.label // Always use latest label
                    )
                }
                return defaultHotkey
            }
            print("✅ HotkeyService: Loaded \(saved.count) custom hotkeys from UserDefaults")
        } catch {
            print("❌ HotkeyService: Failed to decode custom hotkeys: \(error)")
        }
    }

    /// Save current hotkey bindings to UserDefaults
    func saveCustomHotkeys() {
        do {
            let data = try JSONEncoder().encode(registeredHotkeys)
            UserDefaults.standard.set(data, forKey: SettingsKey.customHotkeysData)
        } catch {
            print("❌ HotkeyService: Failed to encode custom hotkeys: \(error)")
        }
    }

    // MARK: - Update / Clear / Restore

    /// Update a hotkey's key combination and persist.
    func updateHotkey(id: String, keyCode: UInt16, modifiers: CGEventFlags) {
        guard let index = registeredHotkeys.firstIndex(where: { $0.id == id }) else { return }
        registeredHotkeys[index].keyCode = keyCode
        registeredHotkeys[index].modifiersRawValue = modifiers.rawValue
        saveCustomHotkeys()
        restartListening()
    }

    /// Clear a hotkey (set to unassigned).
    func clearHotkey(id: String) {
        updateHotkey(id: id, keyCode: 0, modifiers: [])
    }

    /// Restore all hotkeys to factory defaults.
    func restoreDefaults() {
        registeredHotkeys = Self.defaultHotkeys
        UserDefaults.standard.removeObject(forKey: SettingsKey.customHotkeysData)
        restartListening()
    }

    // MARK: - Conflict Detection

    /// Returns any hotkey that conflicts with the given key combination, excluding the specified hotkey ID.
    func conflictingHotkey(keyCode: UInt16, modifiers: CGEventFlags, excludingId: String) -> Hotkey? {
        guard keyCode != 0 else { return nil }
        return registeredHotkeys.first { hotkey in
            hotkey.id != excludingId
                && hotkey.keyCode == keyCode
                && hotkey.modifiersRawValue == modifiers.rawValue
                && !hotkey.isUnassigned
        }
    }

    // MARK: - Display String

    /// Returns a human-readable string for a hotkey (e.g. "⌘⇧4").
    static func displayString(for hotkey: Hotkey) -> String {
        guard !hotkey.isUnassigned else { return "" }

        var result = ""
        let mods = hotkey.modifiers
        if mods.contains(.maskControl) { result += "⌃" }
        if mods.contains(.maskAlternate) { result += "⌥" }
        if mods.contains(.maskShift) { result += "⇧" }
        if mods.contains(.maskCommand) { result += "⌘" }
        result += keyCodeToString(hotkey.keyCode)
        return result
    }

    // MARK: - Start/Stop Listening

    func startListening() {
        guard !isListening else { return }

        // Global monitor — catches events when app is NOT focused (sandbox-safe)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyEvent(event)
            }
        }

        // Local monitor — catches events when app IS focused
        // Check hotkey match synchronously to consume event before it reaches text fields
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let keyCode = event.keyCode
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let matched = self.registeredHotkeys.contains { hotkey in
                !hotkey.isUnassigned && hotkey.keyCode == keyCode && hotkey.nsModifiers == flags
            }
            if matched {
                Task { @MainActor in self.handleKeyEvent(event) }
                return nil
            }
            return event
        }

        isListening = true
        print("✅ HotkeyService: NSEvent monitors active (sandbox-compatible)")
    }

    func stopListening() {
        if let global = globalMonitor {
            NSEvent.removeMonitor(global)
            globalMonitor = nil
        }
        if let local = localMonitor {
            NSEvent.removeMonitor(local)
            localMonitor = nil
        }
        isListening = false
    }

    /// Stop and restart the event monitors to pick up hotkey changes.
    private func restartListening() {
        guard isListening else { return }
        stopListening()
        startListening()
    }

    // MARK: - Event Handling

    /// Returns true if the event was consumed by a hotkey action.
    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let keyCode = event.keyCode
        // Mask out caps lock, num lock, function keys — only check modifier keys we care about
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])

        for hotkey in registeredHotkeys {
            guard !hotkey.isUnassigned else { continue }
            if keyCode == hotkey.keyCode && flags == hotkey.nsModifiers {
                if let action = hotkeyActions[hotkey.id] {
                    action()
                    return true
                }
            }
        }

        return false
    }

    // MARK: - Key Code to String

    /// Maps Carbon virtual key codes to human-readable key names.
    static func keyCodeToString(_ keyCode: UInt16) -> String {
        switch Int(keyCode) {
        // Letters
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        // Numbers
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        // Function keys
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        // Special keys
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "␣"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        // Symbols
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Grave: return "`"
        default: return "Key\(keyCode)"
        }
    }
}
