import SwiftUI

/// SwiftUI toolbar for annotation tool/color/width selection during recording
struct RecordingAnnotationToolbarView: View {
    @Bindable var state: RecordingAnnotationState

    private let colorPresets: [Color] = [.red, .blue, .green, .yellow, .white]
    private let widthPresets: [CGFloat] = [2, 4, 8]

    var body: some View {
        HStack(spacing: 8) {
            // Tool buttons
            toolButtons

            divider

            // Color presets
            colorButtons

            divider

            // Width presets
            widthButtons

            divider

            // Clear all
            Button(action: state.clearAll) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear all annotations")

            // Auto-clear menu
            autoClearMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Subviews

    private var toolButtons: some View {
        HStack(spacing: 2) {
            ForEach(RecordingAnnotationState.availableTools, id: \.self) { tool in
                Button {
                    state.selectedTool = tool
                } label: {
                    Image(systemName: tool.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(
                            state.selectedTool == tool ? .white : .white.opacity(0.5)
                        )
                        .frame(width: 26, height: 26)
                        .background(
                            state.selectedTool == tool ? .white.opacity(0.15) : .clear,
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tool.displayName)
                .help("\(tool.displayName) (\(String(tool.defaultShortcut).uppercased()))")
            }
        }
    }

    private var colorButtons: some View {
        HStack(spacing: 4) {
            ForEach(colorPresets, id: \.self) { color in
                Circle()
                    .fill(color)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle().stroke(.white.opacity(0.3), lineWidth: state.strokeColor == color ? 2 : 0)
                    )
                    .onTapGesture { state.strokeColor = color }
                    .accessibilityLabel("Color: \(color.description)")
            }
        }
    }

    private var widthButtons: some View {
        HStack(spacing: 4) {
            ForEach(widthPresets, id: \.self) { width in
                RoundedRectangle(cornerRadius: 1)
                    .fill(.white.opacity(state.strokeWidth == width ? 1.0 : 0.4))
                    .frame(width: 18, height: width)
                    .onTapGesture { state.strokeWidth = width }
                    .accessibilityLabel("Width: \(Int(width))px")
            }
        }
    }

    private var autoClearMenu: some View {
        Menu {
            Text("Auto-clear: \(state.selectedTool.displayName)")
            Divider()
            ForEach(RecordingAnnotationClearMode.presets, id: \.self) { mode in
                Button {
                    state.toolClearModes[state.selectedTool] = mode
                } label: {
                    HStack {
                        Text(mode.displayName)
                        if state.clearMode(for: state.selectedTool) == mode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "timer")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 26, height: 26)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Auto-clear mode")
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.2))
            .frame(width: 1, height: 20)
    }
}
