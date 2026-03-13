import SwiftUI

/// Menu bar dropdown view — the primary UI entry point for SnapForge.
struct MenuBarView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "hammer.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                Text(String(localized: "menu.title"))
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
                    label: String(localized: "menu.capture_area"),
                    shortcut: "⌘⇧4"
                ) {
                    AppCoordinator.shared.showCaptureOverlay(for: .area)
                }

                MenuBarActionRow(
                    icon: "macwindow",
                    label: String(localized: "menu.capture_window"),
                    shortcut: "⌘⇧W"
                ) {
                    AppCoordinator.shared.showCaptureOverlay(for: .window)
                }

                MenuBarActionRow(
                    icon: "rectangle.inset.filled",
                    label: String(localized: "menu.capture_fullscreen"),
                    shortcut: "⌘⇧3"
                ) {
                    AppCoordinator.shared.showCaptureOverlay(for: .fullscreen)
                }

                MenuBarActionRow(
                    icon: "timer",
                    label: String(localized: "menu.self_timer"),
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
                    label: env.isRecording
                        ? String(localized: "menu.stop_recording")
                        : String(localized: "menu.record_screen"),
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
                    label: String(localized: "menu.ocr_capture"),
                    shortcut: "⌘⇧O"
                ) {
                    AppCoordinator.shared.showCaptureOverlay(for: .ocrCapture)
                }

                MenuBarActionRow(
                    icon: "pin.fill",
                    label: String(localized: "menu.pin_clipboard"),
                    shortcut: ""
                ) {
                    if let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
                        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
                        let frame = NSRect(
                            x: screenFrame.midX - 150,
                            y: screenFrame.midY - 100,
                            width: 300,
                            height: 200
                        )
                        AppCoordinator.shared.pinImage(image, at: frame)
                    } else {
                        NSSound.beep()
                    }
                }

                MenuBarActionRow(
                    icon: "clock.arrow.circlepath",
                    label: String(localized: "menu.capture_history"),
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
                Button(action: {
                    // Activate the app first — required for .accessory policy apps
                    // so the Settings window reliably comes to front.
                    // Async delay is needed: the MenuBarExtra popover dismissal
                    // races with activation, causing openSettings() to silently fail.
                    NSApp.activate(ignoringOtherApps: true)
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        openSettings()
                    }
                }) {
                    Label(String(localized: "menu.settings"), systemImage: "gearshape")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Label(String(localized: "menu.quit"), systemImage: "power")
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
        .clipShape(.rect(cornerRadius: 6))
    }
}
