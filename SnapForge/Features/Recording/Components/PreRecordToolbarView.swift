import SwiftUI

/// Redesigned pre-record toolbar: [x] | [camera] [capture toggle] | [mic] | [Options v] | [Record <badge> v]
struct PreRecordToolbarView: View {
    @Bindable var state: RecordingToolbarState
    let onRecord: () -> Void
    let onCapture: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Close button
            RecordingToolbarIconButton(
                systemName: "xmark",
                action: onCancel,
                accessibilityLabel: "Cancel recording"
            )

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
                Text("Options")
                    .font(.system(size: 12))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $state.showOptionsPopover) {
            RecordingOptionsPopover(state: state)
                .preferredColorScheme(.dark)
        }
        .accessibilityLabel("Recording options")
    }
}
