import SwiftUI

/// Recording indicator overlay — red border with REC badge, timer, and stop button.
struct RecordingIndicatorView: View {
    @State private var elapsedSeconds = 0
    @State private var timer: Timer?
    @State private var isBlinking = true

    var body: some View {
        VStack {
            HStack {
                Spacer()
                // REC badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                        .opacity(isBlinking ? 1.0 : 0.3)
                        .animation(.easeInOut(duration: 0.5).repeatForever(), value: isBlinking)

                    Text("REC")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)

                    Text(formattedTime)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white)

                    Button(action: stopRecording) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                            .frame(width: 20, height: 20)
                            .background(.red, in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.75), in: Capsule())
                .padding(.trailing, 8)
                .padding(.top, 8)
            }
            Spacer()
        }
        .onAppear {
            isBlinking = true
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                DispatchQueue.main.async {
                    elapsedSeconds += 1
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private var formattedTime: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func stopRecording() {
        AppCoordinator.shared.dismissRecordingIndicator()
    }
}
