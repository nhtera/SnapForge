import SwiftUI
import ServiceManagement

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
        let fileAccess = SandboxFileAccessManager.shared
        if let url = fileAccess.chooseExportDirectory() {
            saveLocation = url.path
            // Re-ensure directory exists with new bookmark access
            AppEnvironment.shared.storageService.ensureDefaultDirectoryExists()
        }
    }

    private func shortenedPath(_ path: String) -> String {
        // Use real home path (getpwuid bypasses sandbox container redirect)
        if let pw = getpwuid(getuid()), let homeDir = pw.pointee.pw_dir {
            let realHome = String(cString: homeDir)
            if path.hasPrefix(realHome) {
                return "~" + path.dropFirst(realHome.count)
            }
        }
        // Fallback to sandbox home
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
