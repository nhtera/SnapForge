import SwiftUI

/// Annotation editor view — canvas with tool palette for drawing on captured images.
struct AnnotationView: View {
    let image: NSImage
    @State private var viewModel = AnnotationViewModel()

    var body: some View {
        HSplitView {
            // Canvas area
            ZStack {
                // Background
                Color(nsColor: .controlBackgroundColor)

                // Image
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(40)

                // Annotations canvas (overlay)
                Canvas { context, size in
                    // Render annotations here
                }
                .allowsHitTesting(true)
            }

            // Tool palette (right sidebar)
            ToolPaletteView(viewModel: viewModel)
                .frame(width: 220)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { viewModel.undo() }) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!viewModel.canUndo)
                .help("Undo")

                Button(action: { viewModel.redo() }) {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!viewModel.canRedo)
                .help("Redo")

                Divider()

                Button("Done") {
                    // Export and close
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - Tool Palette

struct ToolPaletteView: View {
    @Bindable var viewModel: AnnotationViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Tool grid
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
                ForEach(AnnotationType.allCases) { tool in
                    ToolButton(
                        tool: tool,
                        isSelected: viewModel.selectedTool == tool
                    ) {
                        viewModel.selectedTool = tool
                    }
                }
            }
            .padding()

            Divider()

            // Tool settings
            VStack(alignment: .leading, spacing: 12) {
                // Color picker
                HStack {
                    Text("Color")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    ColorPicker("", selection: $viewModel.selectedColor)
                        .labelsHidden()
                }

                // Stroke width
                VStack(alignment: .leading, spacing: 4) {
                    Text("Thickness: \(Int(viewModel.strokeWidth))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $viewModel.strokeWidth, in: 1...20, step: 1)
                }

                // Opacity
                VStack(alignment: .leading, spacing: 4) {
                    Text("Opacity: \(Int(viewModel.opacity * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $viewModel.opacity, in: 0.1...1.0, step: 0.1)
                }
            }
            .padding()

            Spacer()
        }
        .background(.background)
    }
}

// MARK: - Tool Button

struct ToolButton: View {
    let tool: AnnotationType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: tool.icon)
                    .font(.system(size: 18))
                Text(tool.rawValue)
                    .font(.system(size: 8))
            }
            .frame(width: 44, height: 44)
            .background(isSelected ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .help(tool.rawValue)
    }
}
