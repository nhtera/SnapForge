import SwiftUI

/// SwiftUI toolbar for annotation tool/color/width selection during recording
struct RecordingAnnotationToolbarView: View {
    @Bindable var state: RecordingAnnotationState

    private let colorPresets: [Color] = [.red, .blue, .green, .yellow, .white]
    private let widthPresets: [CGFloat] = [2, 4, 8]
    @State private var colorObserverTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 8) {
            // Tool buttons
            toolButtons

            divider

            // Color presets
            colorButtons

            divider

            // Width presets (hidden for text/counter/blur/spotlight/laserPointer)
            if state.selectedTool != .text && state.selectedTool != .counter
                && state.selectedTool != .blur && state.selectedTool != .spotlight
                && state.selectedTool != .laserPointer {
                widthButtons
            }

            // Font size presets (shown for text tool only)
            if state.selectedTool == .text {
                fontSizeButtons
            }

            // Blur type toggle (shown for blur tool only)
            if state.selectedTool == .blur {
                blurTypeButtons
            }

            // Laser pointer size presets
            if state.selectedTool == .laserPointer {
                laserSizeButtons
            }

            divider

            // Undo/Redo
            undoRedoButtons

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
                .overlay(alignment: .bottomTrailing) {
                    if state.isShortcutModeActive {
                        Text(String(tool.defaultShortcut).uppercased())
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(.blue, in: RoundedRectangle(cornerRadius: 3))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: state.isShortcutModeActive)
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

            // Custom color picker — rainbow circle button that opens NSColorPanel
            Button {
                let panel = NSColorPanel.shared
                panel.showsAlpha = false
                panel.color = NSColor(state.strokeColor)
                panel.setTarget(nil)
                panel.makeKeyAndOrderFront(nil)
                // Observe color changes via timer since NSColorPanel doesn't have SwiftUI binding
                colorObserverTask?.cancel()
                colorObserverTask = Task { @MainActor in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(100))
                        let panelColor = NSColorPanel.shared.color
                        state.strokeColor = Color(nsColor: panelColor)
                    }
                }
            } label: {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                            center: .center
                        )
                    )
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Custom color")
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

    private let fontSizePresets: [(String, CGFloat)] = [("S", 14), ("M", 20), ("L", 28)]

    private var fontSizeButtons: some View {
        HStack(spacing: 4) {
            ForEach(fontSizePresets, id: \.1) { label, size in
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(state.selectedFontSize == size ? .white : .white.opacity(0.4))
                    .frame(width: 22, height: 22)
                    .background(
                        state.selectedFontSize == size ? .white.opacity(0.15) : .clear,
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                    .onTapGesture { state.selectedFontSize = size }
                    .accessibilityLabel("Font size \(label)")
            }
        }
    }

    private let laserSizePresets: [(String, CGFloat)] = [("S", 8), ("M", 14), ("L", 22)]

    private var laserSizeButtons: some View {
        HStack(spacing: 4) {
            ForEach(laserSizePresets, id: \.1) { label, size in
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(
                        state.laserPointerState.dotSize == size ? .white : .white.opacity(0.4)
                    )
                    .frame(width: 22, height: 22)
                    .background(
                        state.laserPointerState.dotSize == size ? .white.opacity(0.15) : .clear,
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                    .onTapGesture { state.laserPointerState.dotSize = size }
                    .accessibilityLabel("Laser size \(label)")
            }
        }
    }

    private var blurTypeButtons: some View {
        HStack(spacing: 4) {
            ForEach(BlurType.allCases) { blurType in
                Button {
                    state.selectedBlurType = blurType
                } label: {
                    Image(systemName: blurType.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(
                            state.selectedBlurType == blurType ? .white : .white.opacity(0.4)
                        )
                        .frame(width: 26, height: 26)
                        .background(
                            state.selectedBlurType == blurType ? .white.opacity(0.15) : .clear,
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                }
                .buttonStyle(.plain)
                .help(blurType.displayName)
            }
        }
    }

    private var undoRedoButtons: some View {
        HStack(spacing: 2) {
            Button(action: state.undo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(state.canUndo ? 0.8 : 0.2))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(!state.canUndo)
            .help("Undo (⌘Z)")
            .accessibilityLabel("Undo annotation")

            Button(action: state.redo) {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(state.canRedo ? 0.8 : 0.2))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(!state.canRedo)
            .help("Redo (⇧⌘Z)")
            .accessibilityLabel("Redo annotation")
        }
    }

    private var autoClearMenu: some View {
        let currentMode = state.clearMode(for: state.selectedTool)
        return Menu {
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
                .foregroundStyle(.white.opacity(currentMode != .persist ? 0.9 : 0.6))
                .frame(width: 26, height: 26)
                .overlay(alignment: .bottomTrailing) {
                    // Badge showing active auto-clear mode (hidden for .persist)
                    if currentMode != .persist {
                        Text(currentMode.badgeLabel)
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(.orange, in: Capsule())
                            .offset(x: 4, y: 4)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: currentMode)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Auto-clear mode: \(currentMode.displayName)")
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.2))
            .frame(width: 1, height: 20)
    }
}
