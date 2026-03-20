import SwiftUI

// MARK: - Shortcuts Tab

struct ShortcutsSettingsTab: View {
    private var hotkeyService: HotkeyService { AppEnvironment.shared.hotkeyService }
    @AppStorage(SettingsKey.globalShortcutsEnabled) private var globalShortcutsEnabled = true
    @State private var showDisableConfirmation = false
    @State private var systemShortcutsConflict = false
    @State private var isCheckingConflicts = false

    // Screenshot hotkey IDs
    private let screenshotIds = ["captureArea", "captureFullscreen", "captureWindow", "selfTimer"]
    // Recording hotkey IDs
    private let recordingIds = ["startRecording"]
    // Utility hotkey IDs
    private let utilityIds = ["toggleOCR", "colorPicker", "scrollCapture", "captureHistory", "pinFromClipboard"]

    // System Settings URL for keyboard shortcuts
    private let keyboardShortcutsURL =
        "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts"

    var body: some View {
        Form {
            // System Shortcuts conflict status (shown only when enabled)
            if globalShortcutsEnabled {
                Section {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Image(systemName: systemShortcutsConflict ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(systemShortcutsConflict ? .yellow : .green)
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(systemShortcutsConflict ? "Possible conflicts" : "No conflicts detected")
                                .font(.subheadline.weight(.semibold))
                            Text(systemShortcutsConflict
                                 ? "macOS default screenshot shortcuts may override SnapForge."
                                 : "macOS default screenshot shortcuts are disabled. SnapForge shortcuts will work correctly.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            checkSystemShortcutConflicts()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(isCheckingConflicts)
                    }
                } header: {
                    Text("System Shortcuts")
                        .foregroundStyle(systemShortcutsConflict ? .yellow : .green)
                }
            }

            // Global Shortcuts toggle
            Section {
                Toggle(isOn: Binding(
                    get: { globalShortcutsEnabled },
                    set: { newValue in
                        if !newValue {
                            // Show confirmation before disabling
                            showDisableConfirmation = true
                        } else {
                            globalShortcutsEnabled = true
                            hotkeyService.startListening()
                            checkSystemShortcutConflicts()
                        }
                    }
                )) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Shortcuts")
                            Text("Capture from any app")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "keyboard")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Global Shortcuts")
            } footer: {
                if !globalShortcutsEnabled {
                    Text("Use keyboard shortcuts to capture from anywhere.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Only show shortcut sections when enabled
            if globalShortcutsEnabled {
                // Guide
                Section {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                        Text("How to reassign default shortcuts")
                            .font(.subheadline.weight(.semibold))

                        Text("1. Go to System Settings → Keyboard → Keyboard Shortcuts")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            if let url = URL(string: keyboardShortcutsURL) {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: DesignTokens.Spacing.xs) {
                                Image(systemName: "gear")
                                    .font(.caption2)
                                Text("Open System Settings")
                                    .font(.caption.weight(.medium))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, DesignTokens.Spacing.sm)
                            .padding(.vertical, DesignTokens.Spacing.xs)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()

                        Text("2. Select \"Screenshots\" and uncheck system shortcuts")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("3. Then assign ⌘⇧3 and ⌘⇧4 to SnapForge below")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Capture Shortcuts
                Section("Capture Shortcuts") {
                    ForEach(hotkeys(for: screenshotIds)) { hotkey in
                        ShortcutRow(hotkey: hotkey, hotkeyService: hotkeyService)
                    }
                }

                // Recording Shortcuts
                Section("Recording Shortcuts") {
                    ForEach(hotkeys(for: recordingIds)) { hotkey in
                        ShortcutRow(hotkey: hotkey, hotkeyService: hotkeyService)
                    }
                }

                // Utility Shortcuts
                Section("Utility Shortcuts") {
                    ForEach(hotkeys(for: utilityIds)) { hotkey in
                        ShortcutRow(hotkey: hotkey, hotkeyService: hotkeyService)
                    }
                }

                // Annotation Tool Shortcuts (read-only)
                Section {
                    ForEach(AnnotationToolType.allCases) { tool in
                        HStack {
                            Label {
                                Text(tool.displayName)
                            } icon: {
                                Image(systemName: tool.icon)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                            }
                            Spacer()
                            Text(String(tool.defaultShortcut).uppercased())
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                        }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Annotation Tool Shortcuts")
                        Text("Single-key shortcuts when the annotation editor is open.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Restore Defaults (always visible)
            Section {
                HStack {
                    Spacer()
                    Button("Restore Defaults") {
                        hotkeyService.restoreDefaults()
                        if !globalShortcutsEnabled {
                            globalShortcutsEnabled = true
                            hotkeyService.startListening()
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if globalShortcutsEnabled {
                checkSystemShortcutConflicts()
            }
        }
        .alert("Disable Keyboard Shortcuts?", isPresented: $showDisableConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Disable", role: .destructive) {
                globalShortcutsEnabled = false
                hotkeyService.stopListening()
            }
        } message: {
            Text("You won't be able to capture screenshots or recordings using keyboard shortcuts from any app. You'll need to open SnapForge manually to use capture features.")
        }
    }

    private func hotkeys(for ids: [String]) -> [HotkeyService.Hotkey] {
        ids.compactMap { id in
            hotkeyService.registeredHotkeys.first(where: { $0.id == id })
        }
    }

    /// Check if macOS system screenshot shortcuts are enabled (potential conflict).
    /// macOS treats MISSING keys as enabled by default — so if keys 28-31
    /// don't exist in the plist, the system shortcuts ARE active.
    private func checkSystemShortcutConflicts() {
        isCheckingConflicts = true

        // System screenshot shortcut keys:
        // 28 = ⌘⇧3 (Capture entire screen to file)
        // 29 = ⌘⇧4 (Capture selected area to file)
        // 30 = ⌘⇧3 (Capture entire screen to clipboard)
        // 31 = ⌘⇧4 (Capture selected area to clipboard)
        let screenshotKeys = ["28", "29", "30", "31"]

        let plistPath = NSHomeDirectory() + "/Library/Preferences/com.apple.symbolichotkeys.plist"

        if let plist = NSDictionary(contentsOfFile: plistPath) as? [String: Any],
           let hotkeys = plist["AppleSymbolicHotKeys"] as? [String: Any] {
            var hasConflict = false
            for key in screenshotKeys {
                if let entry = hotkeys[key] as? [String: Any] {
                    // Key exists — check if explicitly disabled
                    if let enabled = entry["enabled"] as? Bool, !enabled {
                        continue
                    }
                    // Key exists with enabled=true or no enabled field → conflict
                    hasConflict = true
                    break
                } else {
                    // Key is MISSING from plist → macOS treats it as enabled by default
                    hasConflict = true
                    break
                }
            }
            systemShortcutsConflict = hasConflict
            isCheckingConflicts = false
            return
        }

        // Fallback: Can't read system preferences — assume conflicts exist
        systemShortcutsConflict = true
        isCheckingConflicts = false
    }
}

struct ShortcutRow: View {
    let hotkey: HotkeyService.Hotkey
    let hotkeyService: HotkeyService

    @State private var showConflict = false
    @State private var conflictLabel = ""

    /// Check if this hotkey conflicts with a macOS system shortcut
    private var systemConflictMessage: String? {
        HotkeyService.systemConflict(
            keyCode: hotkey.keyCode,
            modifiers: CGEventFlags(rawValue: hotkey.modifiersRawValue)
        )
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(hotkey.label)
                if !hotkey.description.isEmpty {
                    Text(hotkey.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let conflict = systemConflictMessage {
                    Text("Conflicts with \(conflict)")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }
            Spacer()
            HotkeyRecorderView(
                hotkey: hotkey,
                onRecord: { keyCode, modifiers in
                    if let conflict = hotkeyService.conflictingHotkey(
                        keyCode: keyCode,
                        modifiers: modifiers,
                        excludingId: hotkey.id
                    ) {
                        conflictLabel = conflict.label
                        showConflict = true
                        return
                    }
                    // Warn about system conflict but allow the assignment
                    if let sysConflict = HotkeyService.systemConflict(keyCode: keyCode, modifiers: modifiers) {
                        conflictLabel = sysConflict
                        showConflict = true
                    }
                    hotkeyService.updateHotkey(id: hotkey.id, keyCode: keyCode, modifiers: modifiers)
                },
                onClear: {
                    hotkeyService.clearHotkey(id: hotkey.id)
                }
            )
        }
        .alert("Shortcut Conflict", isPresented: $showConflict) {
            Button("OK") {}
        } message: {
            Text("This shortcut conflicts with \"\(conflictLabel)\". It may not work reliably unless you disable the macOS shortcut in System Settings → Keyboard → Shortcuts → Screenshots.")
        }
    }
}
