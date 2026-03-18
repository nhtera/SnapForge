import SwiftUI

/// PreferenceKey to report annotate button center X for Phase 2 popover positioning
struct AnnotateButtonCenterXKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Recording status bar: [drag] | [dot timer] | [pause] [annotate] | [restart] [trash] | [Stop]
struct RecordingStatusBarView: View {
    private var recorder: ScreenRecordingService { ScreenRecordingService.shared }

    var isGIFMode: Bool = false
    var annotationState: RecordingAnnotationState?
    var onRestart: (() -> Void)?
    var onDelete: () -> Void
    var onStop: () -> Void

    @State private var isBlinking = true
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 0) {
            // Drag handle (visual only — dragging via NSPanel property)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.3))
                .frame(width: 24)
                .accessibilityLabel("Drag to move toolbar")

            RecordingToolbarDivider()

            // Recording indicator + timer
            HStack(spacing: 6) {
                Circle()
                    .fill(.red)
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
                }
                // Audio level indicator
                RecordingAudioLevelIndicator()
            }
            .padding(.horizontal, 8)

            RecordingToolbarDivider()

            // Pause/Resume
            RecordingToolbarIconButton(
                systemName: recorder.isPaused ? "play.fill" : "pause.fill",
                action: { recorder.togglePause() },
                accessibilityLabel: recorder.isPaused ? "Resume recording" : "Pause recording"
            )

            // Annotate button placeholder (wired in Phase 2)
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

            // Delete (with confirmation)
            RecordingToolbarIconButton(
                systemName: "trash",
                action: { showDeleteConfirmation = true },
                accessibilityLabel: "Delete recording"
            )
            .confirmationDialog("Delete this recording?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive, action: onDelete)
                Button("Cancel", role: .cancel) {}
            }

            RecordingToolbarDivider()

            // Stop button
            Button(action: onStop) {
                Text("Stop")
            }
            .buttonStyle(TextToolbarButtonStyle())
            .accessibilityLabel("Stop recording")
            .padding(.trailing, 6)
        }
        .padding(.vertical, RecordingToolbarConstants.verticalPadding)
        .fixedSize()
        .onAppear { isBlinking = true }
    }
}
