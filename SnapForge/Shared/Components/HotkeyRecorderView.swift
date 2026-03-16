import SwiftUI
import Carbon.HIToolbox

/// A reusable view that displays the current keyboard shortcut for a hotkey
/// and allows the user to record a new one by clicking and pressing keys.
///
/// Clean hotkey recorder with × clear button on hover.
struct HotkeyRecorderView: View {
    let hotkey: HotkeyService.Hotkey
    let onRecord: (UInt16, CGEventFlags) -> Void
    let onClear: () -> Void

    @State private var isRecording = false
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            // Main recorder button
            Button {
                isRecording.toggle()
            } label: {
                Group {
                    if isRecording {
                        HStack(spacing: DesignTokens.Spacing.xs) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                            Text("Press shortcut…")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                    } else if hotkey.isUnassigned {
                        Text("Record Shortcut")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(HotkeyService.displayString(for: hotkey))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                }
                .frame(width: 120)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.xs + 2)
                .background {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm + 2)
                        .fill(isRecording
                            ? Color.accentColor.opacity(0.15)
                            : Color.primary.opacity(0.06))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm + 2)
                        .stroke(
                            isRecording
                                ? Color.accentColor.opacity(0.6)
                                : Color.primary.opacity(0.08),
                            lineWidth: 1
                        )
                }
            }
            .buttonStyle(.plain)

            // Clear button — only visible on hover when shortcut is assigned
            if isHovering && !hotkey.isUnassigned && !isRecording {
                Button {
                    onClear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .onHover { hovering in
            withAnimation(DesignTokens.Animation.fast) {
                isHovering = hovering
            }
        }
        .overlay {
            // Invisible key event catcher when recording
            if isRecording {
                KeyRecorderRepresentable { keyCode, modifiers in
                    isRecording = false
                    onRecord(keyCode, modifiers)
                } onCancel: {
                    isRecording = false
                }
                .frame(width: 0, height: 0)
                .opacity(0)
            }
        }
    }
}

// MARK: - NSView Key Recorder

/// An AppKit-bridged view that captures the next keyDown event during hotkey recording.
/// Uses NSEvent local monitor to get raw keyCode and modifier flags.
struct KeyRecorderRepresentable: NSViewRepresentable {
    let onRecord: (UInt16, CGEventFlags) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyRecorderNSView {
        let view = KeyRecorderNSView()
        view.onRecord = onRecord
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: KeyRecorderNSView, context: Context) {}
}

/// Custom NSView that installs a local event monitor to catch keyboard events for recording.
final class KeyRecorderNSView: NSView {
    var onRecord: ((UInt16, CGEventFlags) -> Void)?
    var onCancel: (() -> Void)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }

    private func startMonitoring() {
        stopMonitoring()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            let keyCode = event.keyCode
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])

            // Escape cancels recording
            if keyCode == UInt16(kVK_Escape) {
                self.onCancel?()
                return nil // Consume the event
            }

            // Require at least one modifier key (⌘, ⇧, ⌥, ⌃)
            guard !modifiers.isEmpty else { return event }

            // Convert NSEvent.ModifierFlags to CGEventFlags
            var cgFlags: CGEventFlags = []
            if modifiers.contains(.command) { cgFlags.insert(.maskCommand) }
            if modifiers.contains(.shift) { cgFlags.insert(.maskShift) }
            if modifiers.contains(.option) { cgFlags.insert(.maskAlternate) }
            if modifiers.contains(.control) { cgFlags.insert(.maskControl) }

            self.onRecord?(keyCode, cgFlags)
            return nil // Consume the event
        }
    }

    private func stopMonitoring() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
