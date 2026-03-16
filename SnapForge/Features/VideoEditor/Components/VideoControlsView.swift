import SwiftUI

/// Playback controls for the video editor — play/pause button and time display.
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
}
