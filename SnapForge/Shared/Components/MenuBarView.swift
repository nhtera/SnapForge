import SwiftUI

/// Menu bar dropdown view — the primary UI entry point for SnapForge.
struct MenuBarView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "hammer.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("SnapForge")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Capture Actions
            VStack(spacing: 2) {
                MenuBarActionRow(
                    icon: "rectangle.dashed",
                    label: "Capture Area",
                    shortcut: "⌘⇧4"
                ) {
                    AppCoordinator.shared.showCaptureOverlay(for: .area)
                }

                MenuBarActionRow(
                    icon: "macwindow",
                    label: "Capture Window",
                    shortcut: "⌘⇧W"
                ) {
                    AppCoordinator.shared.showCaptureOverlay(for: .window)
                }

                MenuBarActionRow(
                    icon: "rectangle.inset.filled",
                    label: "Capture Fullscreen",
                    shortcut: "⌘⇧3"
                ) {
                    AppCoordinator.shared.showCaptureOverlay(for: .fullscreen)
                }

                MenuBarActionRow(
                    icon: "timer",
                    label: "Self-Timer Capture",
                    shortcut: "⌘⇧T"
                ) {
                    AppCoordinator.shared.showCaptureOverlay(for: .timedArea)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            // Recording
            VStack(spacing: 2) {
                MenuBarActionRow(
                    icon: env.isRecording ? "stop.circle.fill" : "record.circle",
                    label: env.isRecording ? "Stop Recording" : "Record Screen",
                    shortcut: "⌘⇧5",
                    tintColor: env.isRecording ? .red : nil
                ) {
                    AppCoordinator.shared.toggleRecording()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            // Utilities
            VStack(spacing: 2) {
                MenuBarActionRow(
                    icon: "doc.text.viewfinder",
                    label: "OCR Capture",
                    shortcut: "⌘⇧O"
                ) {
                    AppCoordinator.shared.showCaptureOverlay(for: .area)
                }

                MenuBarActionRow(
                    icon: "pin.fill",
                    label: "Pin from Clipboard",
                    shortcut: ""
                ) {
                    if let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
                        let frame = NSRect(x: 200, y: 200, width: 300, height: 200)
                        AppCoordinator.shared.pinImage(image, at: frame)
                    }
                }

                MenuBarActionRow(
                    icon: "clock.arrow.circlepath",
                    label: "Capture History",
                    shortcut: ""
                ) {
                    AppCoordinator.shared.showHistory()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            // Footer
            HStack(spacing: 12) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Label("Quit", systemImage: "power")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 280)
    }
}

// MARK: - Menu Bar Action Row

struct MenuBarActionRow: View {
    let icon: String
    let label: String
    let shortcut: String
    var tintColor: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 20)
                    .foregroundStyle(tintColor ?? .primary)
                Text(label)
                    .font(.subheadline)
                Spacer()
                if !shortcut.isEmpty {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cornerRadius(6)
    }
}
