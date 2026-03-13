import SwiftUI
import ServiceManagement

/// Settings window — CleanShot X-inspired layout adapted for SnapForge.
/// Tabs: General, Screenshots, Recording, Quick Access, Shortcuts, About
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
    var body: some View {
        Form {
            Section {
                Label("Screenshots", systemImage: "camera.fill")
                    .font(.headline)
            }

            Section {
                ShortcutRow(label: "Capture Area", shortcut: "⌘⇧4")
                ShortcutRow(label: "Capture Fullscreen", shortcut: "⌘⇧3")
                ShortcutRow(label: "Capture Window", shortcut: "⌘⇧W")
                ShortcutRow(label: "Self-Timer", shortcut: "⌘⇧T")
            }

            Section {
                Label("Recording", systemImage: "video.fill")
                    .font(.headline)
            }

            Section {
                ShortcutRow(label: "Record / Stop", shortcut: "⌘⇧5")
            }

            Section {
                Label("Utilities", systemImage: "wand.and.stars")
                    .font(.headline)
            }

            Section {
                ShortcutRow(label: "OCR Capture", shortcut: "⌘⇧O")
                ShortcutRow(label: "Capture History", shortcut: "—")
                ShortcutRow(label: "Pin from Clipboard", shortcut: "—")
            }
        }
        .formStyle(.grouped)
    }
}

struct ShortcutRow: View {
    let label: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(shortcut)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - About Tab

struct AboutSettingsTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "hammer.fill")
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

            Text("Version 1.0.0 (Build 1)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Forge perfect captures.")
                .font(.body)
                .foregroundStyle(.secondary)

            Divider()
                .frame(width: 200)

            VStack(spacing: 6) {
                Text("Built with ❤️ by Tien Nguyen")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Link("Website", destination: URL(string: "https://snapforge.app")!)
                    Link("GitHub", destination: URL(string: "https://github.com/nicktien007")!)
                    Link("Twitter", destination: URL(string: "https://twitter.com/nicktien007")!)
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
