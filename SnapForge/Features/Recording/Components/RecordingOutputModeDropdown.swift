import SwiftUI

/// Record button with output mode badge (Video/GIF) and dropdown chevron
struct RecordingOutputModeDropdown: View {
    @Bindable var state: RecordingToolbarState
    let onRecord: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            // Record button
            Button(action: onRecord) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text("Record")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    // Output mode badge
                    Text(state.outputMode.displayName)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(state.outputMode.badgeColor, in: Capsule())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Chevron dropdown to switch mode
            Menu {
                ForEach(RecordingOutputMode.allCases, id: \.self) { mode in
                    Button {
                        state.outputMode = mode
                    } label: {
                        HStack {
                            Text(mode.displayName)
                            if state.outputMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 16, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            isHovered ? .white.opacity(0.08) : .clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .onHover { isHovered = $0 }
        .animation(RecordingToolbarConstants.hoverAnimation, value: isHovered)
    }
}
