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

            RecordingToolbarDivider()

            // Aspect ratio + size presets
            RecordingAspectRatioMenu(toolbarState: state)

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
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(isOptionsHovered || state.showOptionsPopover ? 0.1 : 0))
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
