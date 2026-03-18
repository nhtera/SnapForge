import SwiftUI

/// Small horizontal bar showing audio level in the recording toolbar
struct RecordingAudioLevelIndicator: View {
    private var recorder: ScreenRecordingService { ScreenRecordingService.shared }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(0.1))

                // Fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(levelColor)
                    .frame(width: geo.size.width * CGFloat(recorder.audioLevel))
                    .animation(DesignTokens.Animation.fast, value: recorder.audioLevel)
            }
        }
        .frame(width: 40, height: 6)
        .accessibilityLabel("Audio level: \(Int(recorder.audioLevel * 100))%")
    }

    private var levelColor: Color {
        let level = recorder.audioLevel
        if level > 0.8 { return .red }
        if level > 0.5 { return .yellow }
        return .green
    }
}
