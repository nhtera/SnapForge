import SwiftUI

/// Redesigned pre-record toolbar: [x] [restore?] | [camera] [capture toggle] | [mic] | [Options v] | [Record <badge> v]
struct PreRecordToolbarView: View {
    @Bindable var state: RecordingToolbarState
    let onRecord: () -> Void
    let onCapture: () -> Void
    let onCancel: () -> Void
    var onRestoreArea: (() -> Void)?

    @State private var isOptionsHovered = false

    var body: some View {
        HStack(spacing: 0) {
            // Close button
            RecordingToolbarIconButton(
                systemName: "xmark",
                action: onCancel,
                accessibilityLabel: "Cancel recording (Esc)"
            )

            // Restore last area button (shown only when valid last area exists)
            if let onRestoreArea {
                RecordingToolbarIconButton(
                    systemName: "arrow.uturn.backward",
                    action: onRestoreArea,
                    accessibilityLabel: "Restore last recording area"
                )
            }

            RecordingToolbarDivider()

            // Camera (screenshot) + capture mode toggle
            HStack(spacing: RecordingToolbarConstants.groupSpacing) {
                RecordingToolbarIconButton(
                    systemName: "camera",
                    action: onCapture,
                    accessibilityLabel: "Take screenshot"
                )
                RecordingCaptureModeToggle(state: state)
            }

            RecordingToolbarDivider()

            // Mic toggle
            RecordingMicToggleButton(state: state)

            // Webcam toggle
            RecordingToolbarIconButton(
                systemName: state.webcamEnabled ? "web.camera.fill" : "web.camera",
                action: { state.webcamEnabled.toggle() },
                accessibilityLabel: state.webcamEnabled ? "Disable webcam" : "Enable webcam",
                isSelected: state.webcamEnabled
            )

            RecordingToolbarDivider()

            // Aspect ratio + size presets
            RecordingAspectRatioMenu(toolbarState: state)

            RecordingToolbarDivider()

            // Presets
            RecordingPresetMenu(state: state)

            RecordingToolbarDivider()

            // Options popover
            optionsButton

            RecordingToolbarDivider()

            // Record button with output mode dropdown
            RecordingOutputModeDropdown(state: state, onRecord: onRecord)
        }
        .fixedSize()
    }

    private var optionsButton: some View {
        Button {
            state.showOptionsPopover.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(isOptionsHovered || state.showOptionsPopover ? 0.12 : 0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isOptionsHovered = $0 }
        .animation(DesignTokens.Animation.fast, value: isOptionsHovered)
        .popover(isPresented: $state.showOptionsPopover) {
            RecordingOptionsPopover(state: state)
                .preferredColorScheme(.dark)
        }
        .accessibilityLabel("Recording options")
    }
}
