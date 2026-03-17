import SwiftUI
import ServiceManagement

/// Settings window with tabbed layout for SnapForge preferences.
/// Tabs: General, Screenshots, Recording, Quick Access, Shortcuts, Permissions, About
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape.fill") {
                GeneralSettingsTab()
            }

            Tab("Screenshots", systemImage: "camera.fill") {
                ScreenshotsSettingsTab()
            }

            Tab("Recording", systemImage: "video.fill") {
                RecordingSettingsTab()
            }

            Tab("Quick Access", systemImage: "rectangle.portrait.and.arrow.forward") {
                QuickAccessSettingsTab()
            }

            Tab("Shortcuts", systemImage: "command") {
                ShortcutsSettingsTab()
            }

            Tab("Permissions", systemImage: "lock.shield") {
                PermissionsSettingsTab()
            }

            Tab("About", systemImage: "info.circle") {
                AboutSettingsTab()
            }
        }
        .frame(width: 560, height: 480)
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("playSounds") private var playSounds = true
    @AppStorage("saveLocation") private var saveLocation = "~/Pictures"
    @AppStorage("hideDesktopIcons") private var hideDesktopIcons = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Start at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            print("❌ Failed to update login item: \(error)")
                            // Revert toggle on failure
                            launchAtLogin = !newValue
                        }
                    }
                    .onAppear {
                        // Sync toggle with actual system state
                        launchAtLogin = (SMAppService.mainApp.status == .enabled)
                    }
            }

            Section("Sounds") {
                Toggle("Play capture sounds", isOn: $playSounds)
            }

            Section("Export Location") {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.blue)
                    Text(shortenedPath(saveLocation))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose...") { chooseSaveLocation() }
                }
            }

            Section("Desktop") {
                Toggle("Hide desktop icons while capturing", isOn: $hideDesktopIcons)
                    .help("Temporarily hides desktop icons during capture for cleaner screenshots")
            }

            Section {
                afterCaptureTable
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("After Capture")
                    Text("Choose what happens after taking a screenshot or recording.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Help") {
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Restart Onboarding")
                            Text("Show the welcome tutorial again")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Restart") {
                        UserDefaults.standard.set(false, forKey: SettingsKey.hasCompletedOnboarding)
                        AppCoordinator.shared.showOnboarding()
                    }
                    .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: After-capture action table

    @AppStorage("autoCopyToClipboard") private var autoCopy = true
    @AppStorage("autoSave") private var autoSave = true
    @AppStorage("showQuickAccess") private var showQuickAccess = true
    @AppStorage("openAnnotateAfterCapture") private var openAnnotate = false
    @AppStorage("pinAfterCapture") private var pinAfterCapture = false

    private var afterCaptureTable: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            // Header
            GridRow {
                Text("Screenshot")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Action")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Divider()

            GridRow {
                Toggle("", isOn: $showQuickAccess).labelsHidden()
                Text("Show Quick Access Overlay")
            }

            GridRow {
                Toggle("", isOn: $autoCopy).labelsHidden()
                Text("Copy to clipboard")
            }

            GridRow {
                Toggle("", isOn: $autoSave).labelsHidden()
                Text("Save to export location")
            }

            GridRow {
                Toggle("", isOn: $openAnnotate).labelsHidden()
                Text("Open Annotate tool")
            }

            GridRow {
                Toggle("", isOn: $pinAfterCapture).labelsHidden()
                Text("Pin to screen")
            }
        }
    }

    private func chooseSaveLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            saveLocation = url.path
        }
    }

    private func shortenedPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - Screenshots Tab

struct ScreenshotsSettingsTab: View {
    @AppStorage("imageFormat") private var imageFormat = "png"
    @AppStorage("jpegQuality") private var jpegQuality = 0.9
    @AppStorage("showMagnifier") private var showMagnifier = true
    @AppStorage("showCrosshair") private var showCrosshair = true
    @AppStorage("showDimensions") private var showDimensions = true
    @AppStorage("captureWindowShadow") private var captureWindowShadow = true
    @AppStorage("timerDelay") private var timerDelay = 5
    @AppStorage("freezeScreen") private var freezeScreen = false

    var body: some View {
        Form {
            Section("Default Format") {
                Picker("Image Format", selection: $imageFormat) {
                    Text("PNG").tag("png")
                    Text("JPEG").tag("jpg")
                    Text("WebP").tag("webp")
                    Text("HEIC").tag("heic")
                }
                .pickerStyle(.segmented)

                if imageFormat == "jpg" || imageFormat == "heic" || imageFormat == "webp" {
                    HStack {
                        Text("Quality")
                        Slider(value: $jpegQuality, in: 0.1...1.0, step: 0.05)
                        Text("\(Int(jpegQuality * 100))%")
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 40)
                    }
                }
            }

            Section("Area Selection") {
                Toggle("Show magnifier", isOn: $showMagnifier)
                Toggle("Show crosshair", isOn: $showCrosshair)
                Toggle("Show dimensions", isOn: $showDimensions)
                Toggle("Freeze screen during capture", isOn: $freezeScreen)
                    .help("Takes a snapshot of the screen first so you can select an area from the frozen frame")
            }

            Section("Window Capture") {
                Toggle("Capture window shadow", isOn: $captureWindowShadow)
                    .help("Hold ⌥ (Option) while capturing to toggle shadow")
            }

            Section("Self-Timer") {
                Picker("Countdown delay", selection: $timerDelay) {
                    Text("3 seconds").tag(3)
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Recording Tab

struct RecordingSettingsTab: View {
    @State private var recordingSubTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $recordingSubTab) {
                Text("General").tag(0)
                Text("Video").tag(1)
                Text("GIF").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 40)
            .padding(.top, 12)

            switch recordingSubTab {
            case 0: RecordingGeneralSubTab()
            case 1: RecordingVideoSubTab()
            case 2: RecordingGIFSubTab()
            default: EmptyView()
            }
        }
    }
}

struct RecordingGeneralSubTab: View {
    @AppStorage("showRecordingControls") private var showControls = true
    @AppStorage("showRecordingTimer") private var showTimer = true
    @AppStorage("showCursorInRecording") private var showCursor = true
    @AppStorage("highlightClicks") private var highlightClicks = false
    @AppStorage("showKeystrokes") private var showKeystrokes = false
    @AppStorage("dimScreenWhileRecording") private var dimScreen = true
    @AppStorage("showRecordingCountdown") private var showCountdown = false

    var body: some View {
        Form {
            Section("Controls") {
                Toggle("Show controls while recording", isOn: $showControls)
                Toggle("Display recording time in menu bar", isOn: $showTimer)
            }

            Section("Cursor") {
                Toggle("Show cursor", isOn: $showCursor)
                Toggle("Highlight clicks", isOn: $highlightClicks)
                    .disabled(!showCursor)
            }

            Section("Keyboard") {
                Toggle("Show keystrokes", isOn: $showKeystrokes)
            }

            Section("Recording Area") {
                Toggle("Dim screen while recording", isOn: $dimScreen)
                Toggle("Show countdown before recording", isOn: $showCountdown)
            }
        }
        .formStyle(.grouped)
    }
}

struct RecordingVideoSubTab: View {
    @AppStorage("recordingFPS") private var recordingFPS = 30
    @AppStorage("recordingCodec") private var recordingCodec = "h264"
    @AppStorage("recordingResolution") private var recordingResolution = "retina"

    var body: some View {
        Form {
            Section("Frame Rate") {
                Picker("FPS", selection: $recordingFPS) {
                    Text("24 fps — cinematic").tag(24)
                    Text("30 fps — standard").tag(30)
                    Text("60 fps — smooth").tag(60)
                }
            }

            Section("Codec") {
                Picker("Video Codec", selection: $recordingCodec) {
                    Text("H.264 — best compatibility").tag("h264")
                    Text("HEVC (H.265) — smaller files").tag("hevc")
                }
            }

            Section("Resolution") {
                Picker("Output Resolution", selection: $recordingResolution) {
                    Text("Retina (2x) — full quality").tag("retina")
                    Text("Standard (1x) — smaller files").tag("standard")
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct RecordingGIFSubTab: View {
    @AppStorage("gifFPS") private var gifFPS = 15
    @AppStorage("gifMaxWidth") private var gifMaxWidth = 640
    @AppStorage("gifQuality") private var gifQuality = 0.8
    @AppStorage("gifLoopCount") private var gifLoopCount = 0

    var body: some View {
        Form {
            Section("Frame Rate") {
                Stepper("GIF FPS: \(gifFPS)", value: $gifFPS, in: 5...30, step: 5)
                Text("Higher FPS = smoother but larger files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Dimensions") {
                Stepper("Max Width: \(gifMaxWidth)px", value: $gifMaxWidth, in: 320...1920, step: 160)
                Text("GIF will be scaled down if wider than this")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Quality") {
                HStack {
                    Text("Color Quality")
                    Slider(value: $gifQuality, in: 0.3...1.0, step: 0.1)
                    Text("\(Int(gifQuality * 100))%")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 40)
                }
            }

            Section("Looping") {
                Picker("Loop Count", selection: $gifLoopCount) {
                    Text("Infinite").tag(0)
                    Text("1 time").tag(1)
                    Text("3 times").tag(3)
                    Text("5 times").tag(5)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Quick Access Tab

struct QuickAccessSettingsTab: View {
    @AppStorage("showQuickAccess") private var showQuickAccess = true
    @AppStorage("quickAccessTimeout") private var quickAccessTimeout = 5.0
    @AppStorage("quickAccessAutoClose") private var autoClose = false
    @AppStorage("quickAccessCloseAfterDrag") private var closeAfterDrag = true

    var body: some View {
        Form {
            Section("Visibility") {
                Toggle("Show Quick Access overlay after capture", isOn: $showQuickAccess)
            }

            Section("Auto-close") {
                Toggle("Auto-close after delay", isOn: $autoClose)
                if autoClose {
                    HStack {
                        Text("Interval")
                        Slider(value: $quickAccessTimeout, in: 3...30, step: 1)
                        Text("\(Int(quickAccessTimeout))s")
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 30)
                    }
                }
            }

            Section("Drag & Drop") {
                Toggle("Close after dragging", isOn: $closeAfterDrag)
                    .help("Hold ⌥ (Option) to keep the overlay open after dragging")
            }
        }
        .formStyle(.grouped)
    }
}

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

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(hotkey.label)
                if !hotkey.description.isEmpty {
                    Text(hotkey.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            Text("This shortcut is already used by \"\(conflictLabel)\". Please choose a different one.")
        }
    }
}

// MARK: - Permissions Tab

struct PermissionsSettingsTab: View {
    private var permissionService: PermissionService { AppEnvironment.shared.permissionService }
    @State private var saveFolderGranted = false
    @State private var isChecking = false

    // System Settings deep-link URLs
    private let screenRecordingURL =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    private let microphoneURL =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
    private let accessibilityURL =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    private let filesAndFoldersURL =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"

    var body: some View {
        Form {
            Section("Permissions") {
                Text("SnapForge requires certain permissions to capture your screen and audio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                permissionRow(
                    icon: "rectangle.inset.filled.and.person.filled",
                    name: "Screen Recording",
                    description: "Required for screenshots and recordings",
                    status: permissionService.screenRecordingStatus,
                    isRequired: true,
                    settingsURL: screenRecordingURL
                )

                permissionRow(
                    icon: "folder.fill",
                    name: "Save Folder",
                    description: "Required to save screenshots and recordings",
                    status: saveFolderGranted ? .granted : .denied,
                    isRequired: true,
                    settingsURL: filesAndFoldersURL
                )

                permissionRow(
                    icon: "mic.fill",
                    name: "Microphone",
                    description: "Optional for voice recording",
                    status: permissionService.microphoneStatus,
                    isRequired: false,
                    settingsURL: microphoneURL
                )

                permissionRow(
                    icon: "hand.raised.fill",
                    name: "Accessibility",
                    description: "Optional for global shortcuts",
                    status: permissionService.accessibilityStatus,
                    isRequired: false,
                    settingsURL: accessibilityURL
                )

                HStack {
                    Spacer()
                    Button {
                        refreshAll()
                    } label: {
                        HStack(spacing: 4) {
                            if isChecking {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("Refresh Status")
                        }
                    }
                    .disabled(isChecking)
                }
                .padding(.top, 4)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAll()
        }
    }

    // MARK: - Permission Row

    @ViewBuilder
    private func permissionRow(
        icon: String,
        name: String,
        description: String,
        status: PermissionService.PermissionStatus,
        isRequired: Bool,
        settingsURL: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .fontWeight(.medium)
                    if isRequired {
                        Text("Required")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(.rect(cornerRadius: 4))
                    }
                }
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: status == .granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                Text(status == .granted ? "Granted" : "Not Granted")
                    .font(.caption)
            }
            .foregroundStyle(status == .granted ? .green : .orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((status == .granted ? Color.green : Color.orange).opacity(0.1))
            .clipShape(.rect(cornerRadius: 6))

            Button("Open Settings") {
                if let url = URL(string: settingsURL) {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Permission Checking

    private func refreshAll() {
        isChecking = true
        permissionService.refreshAll()
        checkSaveFolder()
        isChecking = false
    }

    private func checkSaveFolder() {
        let path = UserDefaults.standard.string(forKey: SettingsKey.saveLocation) ?? ""
        if path.isEmpty {
            saveFolderGranted = false
            return
        }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        saveFolderGranted = FileManager.default.isWritableFile(atPath: url.path)
    }
}

// MARK: - About Tab

struct AboutSettingsTab: View {
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("SnapForge")
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text("Version \(appVersion) (\(buildNumber))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Forge perfect captures.")
                .font(.body)
                .foregroundStyle(.secondary)

            // Check for Updates
            Button {
                UpdaterManager.shared.checkForUpdates()
            } label: {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Check for Updates")
                }
                .font(.body.weight(.medium))
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.vertical, DesignTokens.Spacing.sm)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            }
            .buttonStyle(.plain)

            Divider()
                .frame(width: 200)

            VStack(spacing: 6) {
                Text("Built with ❤️ by Tien Nguyen")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Link("GitHub", destination: URL(string: "https://github.com/nhtera/SnapForge")!)
                    Link("Releases", destination: URL(string: "https://github.com/nhtera/SnapForge-releases/releases")!)
                }
                .font(.caption)
            }

            Spacer()

            // System info
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
