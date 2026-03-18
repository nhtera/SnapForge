import SwiftUI

/// Toggle buttons for switching between fullscreen and area capture modes
struct RecordingCaptureModeToggle: View {
    @Bindable var state: RecordingToolbarState

    var body: some View {
        HStack(spacing: RecordingToolbarConstants.groupSpacing) {
            RecordingToolbarIconButton(
                systemName: "rectangle.inset.filled",
                action: { switchMode(.fullscreen) },
                accessibilityLabel: "Fullscreen recording",
                isSelected: state.captureMode == .fullscreen
            )
            RecordingToolbarIconButton(
                systemName: "rectangle.dashed",
                action: { switchMode(.area) },
                accessibilityLabel: "Area recording",
                isSelected: state.captureMode == .area
            )
        }
    }

    private func switchMode(_ mode: RecordingMode) {
        guard state.captureMode != mode else { return }
        state.captureMode = mode
        state.onCaptureModeChanged?(mode)
    }
}
