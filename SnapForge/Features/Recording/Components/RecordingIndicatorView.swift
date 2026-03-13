import SwiftUI

/// Recording indicator overlay — red border with REC badge, timer, stop/pause controls.
/// Positioned at top of screen during recording.
struct RecordingIndicatorView: View {
    @ObservedObject private var recorder = ScreenRecordingService.shared
    @State private var isBlinking = true

    var body: some View {
        VStack {
            HStack {
                Spacer()
                // REC badge
                HStack(spacing: 8) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                        .opacity(isBlinking ? 1.0 : 0.3)
                        .animation(.easeInOut(duration: 0.5).repeatForever(), value: isBlinking)

                    Text("REC")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)

                    Text(recorder.formattedDuration)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(minWidth: 40)

                    // Pause/Resume button
                    Button(action: {
                        recorder.togglePause()
                    }) {
                        Image(systemName: recorder.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.orange, in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)

                    // Stop button
                    Button(action: {
                        Task {
                            await stopRecording()
                        }
                    }) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                            .frame(width: 22, height: 22)
                            .background(.red, in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.8), in: Capsule())
                .padding(.trailing, 8)
                .padding(.top, 8)
            }
            Spacer()
        }
        .onAppear {
            isBlinking = true
        }
    }

    private func stopRecording() async {
        if let savedURL = await recorder.stopRecording() {
            AppEnvironment.shared.isRecording = false
            print("✅ Recording saved: \(savedURL.path)")
        }
        AppCoordinator.shared.dismissRecordingIndicator()
    }
}
