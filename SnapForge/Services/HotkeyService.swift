import Foundation
import AppKit
import Carbon.HIToolbox

/// Manages global keyboard shortcuts using CGEvent taps.
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

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
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

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }
            let service = Unmanaged<HotkeyService>.fromOpaque(refcon).takeUnretainedValue()
            return service.handleEvent(proxy: proxy, type: type, event: event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap = eventTap else {
            print("⚠️ HotkeyService: Failed to create event tap. Accessibility permission may be required.")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        isListening = true
    }

    func stopListening() {
        guard isListening, let eventTap = eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        isListening = false
    }

    // MARK: - Event Handling

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else { return Unmanaged.passRetained(event) }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        for hotkey in registeredHotkeys {
            if keyCode == hotkey.keyCode && flags.contains(hotkey.modifiers) {
                if let action = hotkeyActions[hotkey.id] {
                    DispatchQueue.main.async { @Sendable in
                        action()
                    }
                    return nil // Consume the event
                }
            }
        }

        return Unmanaged.passRetained(event)
    }

    deinit {
        stopListening()
    }
}
