import SwiftUI

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
