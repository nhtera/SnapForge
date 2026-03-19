import AppKit

/// Monitors modifier key hold to activate annotation shortcut mode.
/// When active, single key presses select annotation tools via AnnotationToolType.defaultShortcut.
@MainActor
final class RecordingAnnotationShortcutMonitor {
    private let config = RecordingAnnotationShortcutConfig.shared
    private weak var state: RecordingAnnotationState?

    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var holdTimer: Timer?
    private var isModifierHeld = false

    /// Start monitoring modifier key hold events
    func start(state: RecordingAnnotationState) {
        self.state = state

        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleFlagsChanged(event)
            }
        }

        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleFlagsChanged(event)
            }
            return event
        }
    }

    /// Stop monitoring and deactivate shortcut mode
    func stop() {
        if let m = globalFlagsMonitor { NSEvent.removeMonitor(m); globalFlagsMonitor = nil }
        if let m = localFlagsMonitor { NSEvent.removeMonitor(m); localFlagsMonitor = nil }
        holdTimer?.invalidate()
        holdTimer = nil
        isModifierHeld = false
        state?.isShortcutModeActive = false
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let isPressed = event.modifierFlags.contains(config.modifier.flag)

        if isPressed {
            guard !isModifierHeld else { return }
            isModifierHeld = true

            let duration = config.holdDuration
            holdTimer?.invalidate()
            holdTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.state?.isShortcutModeActive = true
                }
            }
        } else {
            isModifierHeld = false
            holdTimer?.invalidate()
            holdTimer = nil
            state?.isShortcutModeActive = false
        }
    }

}
