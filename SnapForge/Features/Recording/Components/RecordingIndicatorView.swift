import SwiftUI

/// Recording indicator overlay — shows area border, pre-record toolbar, and during-recording controls.
/// CleanShot X style: select area → see highlighted border + toolbar → click Record → recording starts.
struct RecordingIndicatorView: View {
    @ObservedObject private var recorder = ScreenRecordingService.shared
    @State private var isBlinking = true

    /// Pre-record mode: area is selected but recording hasn't started yet
    let isPreRecord: Bool
    let selectedRect: CGRect
    let onStartVideo: () -> Void
    let onStartGIF: () -> Void
    let onCancel: () -> Void

    init(
        isPreRecord: Bool = false,
        selectedRect: CGRect = .zero,
        onStartVideo: @escaping () -> Void = {},
        onStartGIF: @escaping () -> Void = {},
        onCancel: @escaping () -> Void = {}
    ) {
        self.isPreRecord = isPreRecord
        self.selectedRect = selectedRect
        self.onStartVideo = onStartVideo
        self.onStartGIF = onStartGIF
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            // Area highlight border (always visible)
            areaBorder

            // Toolbar: positioned at bottom center of the selected area
            VStack {
                Spacer()

                if isPreRecord {
                    preRecordToolbar
                } else {
                    recordingToolbar
                }
            }
        }
    }

    // MARK: - Area Border

    private var areaBorder: some View {
        GeometryReader { geo in
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
                .frame(width: geo.size.width, height: geo.size.height)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Pre-Record Toolbar (before recording starts)

    private var preRecordToolbar: some View {
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
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)

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
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)

            divider

            // Cancel button
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .foregroundColor(.white.opacity(0.7))
        }
        .background(.black.opacity(0.85), in: Capsule())
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        .padding(.bottom, 8)
    }

    // MARK: - Recording Toolbar (during active recording)

    private var recordingToolbar: some View {
        HStack(spacing: 0) {
            // REC indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .opacity(isBlinking ? 1.0 : 0.3)
                    .animation(.easeInOut(duration: 0.5).repeatForever(), value: isBlinking)

                Text(recorder.formattedDuration)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(minWidth: 40)
            }
            .padding(.horizontal, 10)

            divider

            // Pause/Resume
            Button(action: { recorder.togglePause() }) {
                Image(systemName: recorder.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            divider

            // Undo (restart) — not implemented yet, placeholder
            Button(action: {
                // Future: undo last segment
            }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            divider

            // Delete (cancel recording)
            Button(action: {
                Task {
                    await cancelRecording()
                }
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            divider

            // Stop (save)
            Button(action: {
                Task {
                    await stopRecording()
                }
            }) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(.red, in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
        }
        .padding(.vertical, 4)
        .background(.black.opacity(0.85), in: Capsule())
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        .padding(.bottom, 8)
        .onAppear { isBlinking = true }
    }

    // MARK: - Helpers

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.2))
            .frame(width: 1, height: 20)
    }

    private func stopRecording() async {
        if let savedURL = await recorder.stopRecording() {
            AppEnvironment.shared.isRecording = false
            print("✅ Recording saved: \(savedURL.path)")
        }
        AppCoordinator.shared.dismissRecordingIndicator()
    }

    private func cancelRecording() async {
        await recorder.cancelRecording()
        AppEnvironment.shared.isRecording = false
        AppCoordinator.shared.dismissRecordingIndicator()
    }
}
