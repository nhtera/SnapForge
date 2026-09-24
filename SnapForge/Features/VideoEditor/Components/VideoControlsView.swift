import SwiftUI

/// Playback controls for the video editor — play/pause button, time display, and speed picker.
struct VideoControlsView: View {
    @Bindable var state: VideoEditorState

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // Play/Pause button
            Button(action: { state.togglePlayback() }) {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            // Speed picker
            speedPicker

            // Time display
            HStack(spacing: DesignTokens.Spacing.xs) {
                Text(state.formattedCurrentTime)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text("/")
                    .font(.caption)
                    .foregroundStyle(.quaternary)

                Text(state.formattedDuration)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Trimmed duration
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: "scissors")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(state.formattedTrimmedDuration)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Speed Picker

    private var speedPicker: some View {
        Menu {
            ForEach(VideoEditorState.speedOptions, id: \.self) { speed in
                Button(speedLabel(speed)) {
                    state.playbackSpeed = speed
                    if state.isPlaying {
                        state.player.rate = speed
                    }
                }
            }
        } label: {
            Text(speedLabel(state.playbackSpeed))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.quaternary.opacity(0.5), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Playback speed")
    }

    private func speedLabel(_ speed: Float) -> String {
        speed == 1.0 ? "1x" : String(format: "%.1fx", speed)
    }
}
