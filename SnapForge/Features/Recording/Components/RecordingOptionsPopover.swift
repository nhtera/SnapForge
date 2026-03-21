import SwiftUI

/// Recording settings popover styled — icons, toggle switches, dark appearance
struct RecordingOptionsPopover: View {
    @Bindable var state: RecordingToolbarState
    @State private var selectedFPS: Int = max(24, UserDefaults.standard.integer(forKey: SettingsKey.recordingFPS))
    @AppStorage(SettingsKey.hideDesktopIcons) private var hideDesktopIcons = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title header
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                Text("Recording Settings")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .padding(.bottom, 14)

            // Format section
            SettingsSection(title: "Format", icon: "doc") {
                HStack(spacing: 6) {
                    ForEach(VideoFormat.allCases, id: \.self) { format in
                        OptionPill(
                            title: format.rawValue.uppercased(),
                            isSelected: state.videoFormat == format,
                            action: { state.videoFormat = format }
                        )
                    }
                }
            }

            // Quality section
            SettingsSection(title: "Quality", icon: "sparkles") {
                HStack(spacing: 6) {
                    ForEach(VideoQuality.allCases, id: \.self) { quality in
                        OptionPill(
                            title: quality.rawValue.capitalized,
                            isSelected: state.videoQuality == quality,
                            action: { state.videoQuality = quality }
                        )
                    }
                }
            }

            // Frame Rate section
            SettingsSection(title: "Frame Rate", icon: "gauge.with.needle") {
                HStack(spacing: 6) {
                    ForEach([24, 30, 60], id: \.self) { fps in
                        OptionPill(
                            title: "\(fps) FPS",
                            isSelected: selectedFPS == fps,
                            action: {
                                selectedFPS = fps
                                UserDefaults.standard.set(fps, forKey: SettingsKey.recordingFPS)
                            }
                        )
                    }
                }
            }

            Divider().padding(.vertical, 10)

            // Audio section
            SettingsSection(title: "Audio", icon: "speaker.wave.2") {
                VStack(spacing: 8) {
                    Toggle(isOn: $state.isSystemAudioEnabled) {
                        Label("System Audio", systemImage: "speaker.wave.2")
                            .font(.system(size: 12))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    Toggle(isOn: $state.isMicEnabled) {
                        Label("Microphone", systemImage: "mic")
                            .font(.system(size: 12))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            Divider().padding(.vertical, 10)

            // Overlays section
            SettingsSection(title: "Overlays", icon: "square.3.layers.3d") {
                VStack(spacing: 8) {
                    Toggle(isOn: $state.highlightClicks) {
                        Label("Highlight Clicks", systemImage: "cursorarrow.click.2")
                            .font(.system(size: 12))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    Toggle(isOn: $state.showKeystrokes) {
                        Label("Show Keystrokes", systemImage: "keyboard")
                            .font(.system(size: 12))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    Toggle(isOn: $state.webcamEnabled) {
                        Label("Webcam Overlay", systemImage: "web.camera")
                            .font(.system(size: 12))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            Divider().padding(.vertical, 10)

            // Privacy & Desktop section
            SettingsSection(title: "Privacy", icon: "bell.slash") {
                VStack(spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: SettingsKey.suppressNotificationsWhileRecording) },
                        set: { UserDefaults.standard.set($0, forKey: SettingsKey.suppressNotificationsWhileRecording) }
                    )) {
                        Label("Suppress Notifications", systemImage: "bell.slash")
                            .font(.system(size: 12))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    Toggle(isOn: $hideDesktopIcons) {
                        Label("Hide Desktop Icons", systemImage: "eye.slash")
                            .font(.system(size: 12))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }
        }
        .padding(16)
        .frame(width: 260)
        .font(.system(size: 12))
        .tint(.accentColor)
        .modifier(ForceDarkAppearance())
        .onAppear {
            state.reloadFromDefaults()
            selectedFPS = max(24, UserDefaults.standard.integer(forKey: SettingsKey.recordingFPS))
        }
    }
}

// MARK: - Force Dark Appearance

/// Forces the hosting NSPopover window to use dark appearance
private struct ForceDarkAppearance: ViewModifier {
    func body(content: Content) -> some View {
        content.background(DarkAppearanceSetter())
    }
}

private struct DarkAppearanceSetter: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.appearance = NSAppearance(named: .darkAqua)
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.appearance = NSAppearance(named: .darkAqua)
    }
}

// MARK: - Private Components

/// Section with icon + title label
private struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(.bottom, 4)
    }
}

/// Selectable pill button for format/quality options
private struct OptionPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    isSelected
                        ? Color.accentColor
                        : (isHovered ? Color.primary.opacity(0.1) : Color.primary.opacity(0.05)),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }
}
