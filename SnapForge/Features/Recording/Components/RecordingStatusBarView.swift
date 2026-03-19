import SwiftUI

/// PreferenceKey to report annotate button center X for popover positioning
struct AnnotateButtonCenterXKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Recording status bar: [drag] | [dot timer res] | [pause] [annotate] | [restart] [trash] | [Stop]
struct RecordingStatusBarView: View {
    private var recorder: ScreenRecordingService { ScreenRecordingService.shared }

    var isGIFMode: Bool = false
    var annotationState: RecordingAnnotationState?
    var recordingSize: CGSize?
    var onRestart: (() -> Void)?
    var onDelete: () -> Void
    var onStop: () -> Void

    @State private var isBlinking = true
    @State private var showDeletePopover = false

    var body: some View {
        HStack(spacing: 0) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.3))
                .frame(width: 24)
                .accessibilityLabel("Drag to move toolbar")

            RecordingToolbarDivider()

            // Recording indicator + timer (dims when paused)
            HStack(spacing: 6) {
                Circle()
                    .fill(recorder.isPaused ? .orange : .red)
                    .frame(width: 8, height: 8)
                    .opacity(isBlinking ? 1.0 : 0.3)
                    .animation(.easeInOut(duration: 0.5).repeatForever(), value: isBlinking)

                if isGIFMode {
                    Text("GIF")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.yellow, in: RoundedRectangle(cornerRadius: 3))
                }

                if UserDefaults.standard.bool(forKey: SettingsKey.showRecordingTimer) {
                    Text(recorder.formattedDuration)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(minWidth: 40)
                        .contentTransition(.numericText())
                        .animation(.linear(duration: 0.2), value: recorder.formattedDuration)
                }

                // Resolution label
                if let size = recordingSize {
                    Text("\(Int(size.width))x\(Int(size.height))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }

                // FPS indicator — colored dot signals health, exact number on hover
                HStack(spacing: 3) {
                    Circle()
                        .fill(fpsIndicatorColor)
                        .frame(width: 6, height: 6)
                    Text("fps")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                }
                .help(recorder.currentFPS > 0 ? "\(recorder.currentFPS) fps" : "Measuring…")

                RecordingAudioLevelIndicator()
            }
            .padding(.horizontal, 8)
            .opacity(recorder.isPaused ? 0.5 : 1.0)
            .animation(.easeInOut(duration: 0.3), value: recorder.isPaused)

            RecordingToolbarDivider()

            // Pause/Resume
            RecordingToolbarIconButton(
                systemName: recorder.isPaused ? "play.fill" : "pause.fill",
                action: { recorder.togglePause() },
                accessibilityLabel: recorder.isPaused ? "Resume recording" : "Pause recording"
            )

            // Annotate toggle
            RecordingToolbarIconButton(
                systemName: "pencil.tip.crop.circle",
                action: { annotationState?.isAnnotationEnabled.toggle() },
                accessibilityLabel: "Toggle annotations",
                isSelected: annotationState?.isAnnotationEnabled ?? false
            )
            .overlay(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: AnnotateButtonCenterXKey.self,
                        value: geo.frame(in: .global).midX
                    )
                }
            )

            RecordingToolbarDivider()

            // Restart
            if let onRestart {
                RecordingToolbarIconButton(
                    systemName: "arrow.counterclockwise",
                    action: onRestart,
                    accessibilityLabel: "Restart recording"
                )
            }

            // Delete (inline popover confirmation)
            RecordingToolbarIconButton(
                systemName: "trash",
                action: { showDeletePopover = true },
                accessibilityLabel: "Delete recording"
            )
            .popover(isPresented: $showDeletePopover) {
                VStack(spacing: 8) {
                    Text("Delete recording?")
                        .font(.system(size: 12, weight: .medium))
                    HStack(spacing: 8) {
                        Button("Cancel") { showDeletePopover = false }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                        Button("Delete") { onDelete() }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .controlSize(.small)
                    }
                }
                .padding(12)
            }

            RecordingToolbarDivider()

            // Stop button
            Button(action: onStop) {
                Text("Stop")
            }
            .buttonStyle(TextToolbarButtonStyle())
            .accessibilityLabel("Stop recording (⌘⇧R)")
            .padding(.trailing, 6)
        }
        .padding(.vertical, RecordingToolbarConstants.verticalPadding)
        .fixedSize()
        .onAppear { isBlinking = true }
    }

    /// FPS indicator dot color: gray when not measured, green/yellow/red based on performance.
    private var fpsIndicatorColor: Color {
        let fps = recorder.currentFPS
        guard fps > 0 else { return .white.opacity(0.15) }
        let targetFPS = max(UserDefaults.standard.integer(forKey: SettingsKey.recordingFPS), 30)
        if fps >= targetFPS - 3 { return .green.opacity(0.7) }
        if fps >= targetFPS / 2 { return .yellow.opacity(0.7) }
        return .red.opacity(0.7)
    }
}
