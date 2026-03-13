import Foundation
import AppKit
import Carbon.HIToolbox

/// Manages global keyboard shortcuts using NSEvent monitors (sandbox-compatible).
@MainActor
@Observable
final class HotkeyService {

    struct Hotkey: Identifiable, Codable, Hashable {
        let id: String
        var keyCode: UInt16
        var modifiersRawValue: UInt64
        var label: String

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

        init(id: String, keyCode: UInt16, modifiers: CGEventFlags, label: String) {
            self.id = id
            self.keyCode = keyCode
            self.modifiersRawValue = modifiers.rawValue
            self.label = label
        }

        static let captureArea = Hotkey(
            id: "captureArea",
            keyCode: UInt16(kVK_ANSI_4),
            modifiers: [.maskCommand, .maskShift],
            label: "Capture Area (⌘⇧4)"
        )

        static let captureFullscreen = Hotkey(
            id: "captureFullscreen",
            keyCode: UInt16(kVK_ANSI_3),
            modifiers: [.maskCommand, .maskShift],
            label: "Capture Fullscreen (⌘⇧3)"
        )

        static let captureWindow = Hotkey(
            id: "captureWindow",
            keyCode: UInt16(kVK_ANSI_W),
            modifiers: [.maskCommand, .maskShift],
            label: "Capture Window (⌘⇧W)"
        )

        static let startRecording = Hotkey(
            id: "startRecording",
            keyCode: UInt16(kVK_ANSI_5),
            modifiers: [.maskCommand, .maskShift],
            label: "Start Recording (⌘⇧5)"
        )

        static let toggleOCR = Hotkey(
            id: "toggleOCR",
            keyCode: UInt16(kVK_ANSI_O),
            modifiers: [.maskCommand, .maskShift],
            label: "OCR Capture (⌘⇧O)"
        )
    }

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var hotkeyActions: [String: @Sendable () -> Void] = [:]

    var registeredHotkeys: [Hotkey] = [
        .captureArea,
        .captureFullscreen,
        .captureWindow,
        .startRecording,
        .toggleOCR,
    ]

    var isListening = false

    // MARK: - Registration

    func register(hotkey: Hotkey, action: @escaping @Sendable () -> Void) {
        hotkeyActions[hotkey.id] = action
    }

    // MARK: - Start/Stop Listening

    func startListening() {
        guard !isListening else { return }

        // Global monitor — catches events when app is NOT focused (sandbox-safe)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        // Local monitor — catches events when app IS focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let consumed = self.handleKeyEvent(event)
            return consumed ? nil : event
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

    // MARK: - Event Handling

    /// Returns true if the event was consumed by a hotkey action.
    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let keyCode = event.keyCode
        // Mask out caps lock, num lock, function keys — only check modifier keys we care about
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])

        for hotkey in registeredHotkeys {
            if keyCode == hotkey.keyCode && flags == hotkey.nsModifiers {
                if let action = hotkeyActions[hotkey.id] {
                    action()
                    return true
                }
            }
        }

        return false
    }

}
