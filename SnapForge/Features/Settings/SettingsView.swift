import SwiftUI

/// Settings window with General, Shortcuts, and Advanced tabs.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            ShortcutsSettingsTab()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            AdvancedSettingsTab()
                .tabItem {
                    Label("Advanced", systemImage: "wrench.and.screwdriver")
                }

            AboutSettingsTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @AppStorage("saveLocation") private var saveLocation = "~/Pictures"
    @AppStorage("imageFormat") private var imageFormat = "png"
    @AppStorage("jpegQuality") private var jpegQuality = 0.9
    @AppStorage("showQuickAccess") private var showQuickAccess = true
    @AppStorage("quickAccessTimeout") private var quickAccessTimeout = 5.0
    @AppStorage("autoCopyToClipboard") private var autoCopyToClipboard = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Form {
            Section("Save Location") {
                HStack {
                    Text(saveLocation)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose...") {
                        chooseSaveLocation()
                    }
                }
            }

            Section("Default Format") {
                Picker("Image Format", selection: $imageFormat) {
                    ForEach(ImageExportFormat.allCases) { format in
                        Text(format.rawValue).tag(format.fileExtension)
                    }
                }

                if imageFormat == "jpg" || imageFormat == "heic" {
                    Slider(value: $jpegQuality, in: 0.1...1.0, step: 0.1) {
                        Text("Quality: \(Int(jpegQuality * 100))%")
                    }
                }
            }

            Section("Behavior") {
                Toggle("Show Quick Access overlay after capture", isOn: $showQuickAccess)

                if showQuickAccess {
                    Stepper("Auto-dismiss after \(Int(quickAccessTimeout))s", value: $quickAccessTimeout, in: 3...30, step: 1)
                }

                Toggle("Auto-copy to clipboard", isOn: $autoCopyToClipboard)
                Toggle("Launch at login", isOn: $launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .padding()
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
}

// MARK: - Shortcuts Tab

struct ShortcutsSettingsTab: View {
    var body: some View {
        Form {
            Section("Screenshot") {
                ShortcutRow(label: "Capture Area", shortcut: "⌘⇧4")
                ShortcutRow(label: "Capture Window", shortcut: "⌘⇧W")
                ShortcutRow(label: "Capture Fullscreen", shortcut: "⌘⇧3")
                ShortcutRow(label: "Self-Timer", shortcut: "⌘⇧T")
            }

            Section("Recording") {
                ShortcutRow(label: "Record Screen", shortcut: "⌘⇧5")
            }

            Section("Utilities") {
                ShortcutRow(label: "OCR Capture", shortcut: "⌘⇧O")
            }
        }
        .formStyle(.grouped)
        .padding()
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
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

// MARK: - Advanced Tab

struct AdvancedSettingsTab: View {
    @AppStorage("showMagnifier") private var showMagnifier = true
    @AppStorage("showCrosshair") private var showCrosshair = true
    @AppStorage("recordingFPS") private var recordingFPS = 30
    @AppStorage("recordingCodec") private var recordingCodec = "h264"
    @AppStorage("gifFPS") private var gifFPS = 15
    @AppStorage("gifMaxWidth") private var gifMaxWidth = 640

    var body: some View {
        Form {
            Section("Capture") {
                Toggle("Show magnifier during capture", isOn: $showMagnifier)
                Toggle("Show crosshair during capture", isOn: $showCrosshair)
            }

            Section("Recording") {
                Picker("FPS", selection: $recordingFPS) {
                    Text("24 fps").tag(24)
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }

                Picker("Codec", selection: $recordingCodec) {
                    Text("H.264").tag("h264")
                    Text("HEVC (H.265)").tag("hevc")
                }
            }

            Section("GIF") {
                Stepper("GIF FPS: \(gifFPS)", value: $gifFPS, in: 5...30, step: 5)
                Stepper("Max Width: \(gifMaxWidth)px", value: $gifMaxWidth, in: 320...1920, step: 160)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - About Tab

struct AboutSettingsTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "hammer.fill")
                .font(.system(size: 64))
                .foregroundStyle(.accent)

            Text("SnapForge")
                .font(.title)
                .fontWeight(.bold)

            Text("Version 1.0.0")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Forge perfect captures.")
                .font(.body)
                .foregroundStyle(.secondary)

            Divider()
                .frame(width: 200)

            Text("Built with ❤️ by Tien Nguyen")
                .font(.caption)
                .foregroundStyle(.secondary)

            Link("Website", destination: URL(string: "https://snapforge.app")!)
                .font(.caption)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
