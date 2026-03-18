import SwiftUI

/// Reusable icon button for recording toolbars with hover and selection state
struct RecordingToolbarIconButton: View {
    let systemName: String
    let action: () -> Void
    let accessibilityLabel: String
    var isSelected: Bool = false

    @State private var isHovered = false

    private var foregroundOpacity: Double {
        isSelected ? 1.0 : (isHovered ? 0.85 : 0.5)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: RecordingToolbarConstants.iconSize))
                .foregroundStyle(.white.opacity(foregroundOpacity))
                .frame(
                    width: RecordingToolbarConstants.buttonSize,
                    height: RecordingToolbarConstants.buttonSize
                )
                .background(
                    isHovered
                        ? .white.opacity(0.1)
                        : .clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(RecordingToolbarConstants.hoverAnimation, value: isHovered)
    }
}
