import SwiftUI

/// PreferenceKey to report annotate button center X for popover positioning
struct AnnotateButtonCenterXKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Recording status bar — minimal design inspired by CleanShot X.
/// Primary: [drag] | [dot timer] [fps-dot] [audio] | [pause] [annotate] | [restart] [trash] | [Stop]
/// Secondary info (resolution, file size) shown on hover tooltip.
struct RecordingStatusBarView: View {
    private var recorder: ScreenRecordingService { ScreenRecordingService.shared }

    var isGIFMode: Bool = false
    var annotationState: RecordingAnnotationState?
    var recordingSize: CGSize?
    var onRestart: (() -> Void)?
    var onDelete: () -> Void
    var onStop: () -> Void

    @State private var isBlinking = true
    @State private var deleteProgress: CGFloat = 0
    @State private var isHoldingDelete = false
    @State private var deleteShake = false
    @State private var deleteCompleted = false

    var body: some View {
        HStack(spacing: 0) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.3))
                .frame(width: 24)
                .accessibilityLabel("Drag to move toolbar")

            RecordingToolbarDivider()

            // Recording indicator group — compact, hover for details
            recordingInfoGroup
                .padding(.horizontal, 8)
                .opacity(recorder.isPaused ? 0.4 : 1.0)
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

            // Delete (hold-to-delete with circular progress)
            holdToDeleteButton

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

    // MARK: - Recording Info Group

    /// Compact recording info: just red dot, timer, GIF badge, paused badge, FPS dot, audio.
    /// Resolution + file size are shown on hover tooltip — keeps toolbar narrow.
    private var recordingInfoGroup: some View {
        HStack(spacing: 6) {
            // Blinking recording dot
            Circle()
                .fill(recorder.isPaused ? .orange : .red)
                .frame(width: 8, height: 8)
                .opacity(isBlinking ? 1.0 : 0.3)
                .animation(.easeInOut(duration: 0.5).repeatForever(), value: isBlinking)

            // GIF mode badge
            if isGIFMode {
                Text("GIF")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.yellow, in: RoundedRectangle(cornerRadius: 3))
            }

            // Timer — hover shows full metadata
            if UserDefaults.standard.bool(forKey: SettingsKey.showRecordingTimer) {
                Text(recorder.formattedDuration)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(minWidth: 44)
                    .contentTransition(.numericText())
                    .animation(.linear(duration: 0.2), value: recorder.formattedDuration)
                    .help(detailTooltip)
            }

            // Paused badge
            if recorder.isPaused {
                Text("PAUSED")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
            }

            // FPS: just the colored dot (no number) — hover for exact fps
            Circle()
                .fill(fpsIndicatorColor)
                .frame(width: 7, height: 7)
                .help(fpsTooltip)

            RecordingAudioLevelIndicator()
        }
    }

    /// Tooltip with all secondary metadata — shown on hover over timer
    private var detailTooltip: String {
        var lines: [String] = []
        if let size = recordingSize {
            lines.append("\(Int(size.width))×\(Int(size.height))")
        }
        if UserDefaults.standard.bool(forKey: SettingsKey.showEstimatedFileSize),
           !recorder.estimatedFileSize.isEmpty {
            lines.append(recorder.estimatedFileSize)
        }
        if recorder.currentFPS > 0 {
            lines.append("\(recorder.currentFPS) fps")
        }
        return lines.joined(separator: " · ")
    }

    /// FPS tooltip text
    private var fpsTooltip: String {
        recorder.currentFPS > 0 ? "\(recorder.currentFPS) fps" : "Measuring…"
    }

    // MARK: - Hold-to-Delete Button

    /// Hold for 0.7s to delete — shows circular progress ring. Short tap shakes as a hint.
    private var holdToDeleteButton: some View {
        let holdDuration: Double = 0.7

        return Image(systemName: "trash")
            .font(.system(size: RecordingToolbarConstants.iconSize))
            .foregroundStyle(deleteCompleted ? .red : .white.opacity(0.7))
            .frame(width: RecordingToolbarConstants.buttonSize, height: RecordingToolbarConstants.buttonSize)
            .background(
                Circle()
                    .trim(from: 0, to: deleteProgress)
                    .stroke(.red, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 24, height: 24)
                    .opacity(isHoldingDelete ? 1 : 0)
            )
            .scaleEffect(isHoldingDelete ? 1.1 : 1.0)
            .offset(x: deleteShake ? -3 : 0)
            .animation(.easeInOut(duration: 0.1), value: isHoldingDelete)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isHoldingDelete else { return }
                        isHoldingDelete = true
                        withAnimation(.linear(duration: holdDuration)) {
                            deleteProgress = 1.0
                        }
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(Int(holdDuration * 1000)))
                            guard isHoldingDelete else { return }
                            deleteCompleted = true
                            try? await Task.sleep(for: .milliseconds(150))
                            onDelete()
                        }
                    }
                    .onEnded { _ in
                        if deleteProgress < 1.0 && !deleteCompleted {
                            withAnimation(.spring(response: 0.1, dampingFraction: 0.3)) {
                                deleteShake = true
                            }
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(300))
                                deleteShake = false
                            }
                        }
                        isHoldingDelete = false
                        withAnimation(.easeOut(duration: 0.15)) {
                            deleteProgress = 0
                        }
                    }
            )
            .accessibilityLabel("Delete recording (hold)")
            .help("Hold to delete recording")
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
