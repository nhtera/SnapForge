import SwiftUI

// MARK: - Recording Area Border View (click-through overlay)

/// Just the area highlight border — rendered in a click-through window.
struct RecordingBorderView: View {
    let isPreRecord: Bool

    @State private var isBlinking = true

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .strokeBorder(
                isPreRecord
                    ? Color.accentColor
                    : Color.red.opacity(isBlinking ? 0.9 : 0.5),
                style: isPreRecord
                    ? StrokeStyle(lineWidth: 2, dash: [8, 4])
                    : StrokeStyle(lineWidth: 2),
                antialiased: true
            )
            .animation(.easeInOut(duration: 0.8).repeatForever(), value: isBlinking)
            .onAppear { isBlinking = true }
    }
}

// MARK: - Pre-Record Toolbar (before recording starts)

/// Floating toolbar below selected area: Record / GIF / Cancel
struct PreRecordToolbarView: View {
    let onStartVideo: () -> Void
    let onStartGIF: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Record Video button
            Button(action: onStartVideo) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                    Text("Record")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)

            divider

            // GIF button
            Button(action: onStartGIF) {
                HStack(spacing: 6) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 10))
                    Text("GIF")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)

            divider

            // Cancel button
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.7))
        }
        .fixedSize()
        .background(.black.opacity(0.85), in: Capsule())
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.2))
            .frame(width: 1, height: 20)
    }
}

// MARK: - Recording Toolbar (during active recording)

/// Floating toolbar: REC/GIF badge + timer + pause/stop/delete.
/// Stop and cancel route through AppCoordinator so GIF conversion runs.
struct RecordingToolbarView: View {
    @State private var recorder = ScreenRecordingService.shared
    @State private var isBlinking = true

    /// Whether recording in GIF mode (shows GIF badge)
    var isGIFMode: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            // REC / GIF indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .opacity(isBlinking ? 1.0 : 0.3)
                    .animation(.easeInOut(duration: 0.5).repeatForever(), value: isBlinking)

                if isGIFMode {
                    Text("GIF")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.yellow, in: RoundedRectangle(cornerRadius: 3))
                }

                Text(recorder.formattedDuration)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(minWidth: 40)
            }
            .padding(.horizontal, 10)

            divider

            // Pause/Resume
            Button(action: { recorder.togglePause() }) {
                Image(systemName: recorder.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            divider

            // Delete (cancel recording without saving)
            Button(action: {
                Task {
                    do {
                        await AppCoordinator.shared.cancelRecording()
                    }
                }
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            divider

            // Stop (save — triggers GIF conversion if in GIF mode)
            Button(action: {
                Task {
                    do {
                        await AppCoordinator.shared.stopRecording()
                    }
                }
            }) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
                    .background(.red, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
        }
        .padding(.vertical, 4)
        .fixedSize()
        .background(.black.opacity(0.85), in: Capsule())
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        .onAppear { isBlinking = true }
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.2))
            .frame(width: 1, height: 20)
    }
}

// MARK: - First-Mouse Hosting View

/// Custom NSHostingView that accepts the first mouse click without requiring window activation.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
