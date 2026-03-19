import SwiftUI

/// Controls view for GIF editor mode.
/// Shows frame count and duration info instead of playback controls.
struct GIFControlsView: View {
    @Bindable var state: VideoEditorState

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // GIF badge
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
                Text("GIF")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
            }

            Spacer()

            // Frame and duration info
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: "film.stack")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(state.gifTrimmedFrameCount)/\(state.gifFrameCount) frames")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)

                Text(String(format: "%.1fs", state.gifTrimmedDuration))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
