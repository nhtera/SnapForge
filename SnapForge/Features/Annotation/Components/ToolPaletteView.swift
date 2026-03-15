import SwiftUI

/// Tool palette sidebar for the annotation editor.
/// Displays tool grid, color picker, stroke settings, and text styling controls.
struct ToolPaletteView: View {
  @Bindable var state: AnnotateState

  /// Keep KVO observation alive — static so it persists across view rebuilds
  @State private var colorPanelObservation: NSKeyValueObservation?

  var body: some View {
    VStack(spacing: 0) {
      // Tool grid
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 56))], spacing: 6) {
        ForEach(AnnotationToolType.allCases) { tool in
          ToolButton(
            tool: tool,
            isSelected: state.selectedTool == tool
          ) {
            state.selectedTool = tool

            // Auto-initialize crop when crop tool is selected
            if tool == .crop && state.hasImage {
              if state.cropRect == nil {
                state.initializeCrop()
              } else {
                state.isCropActive = true
              }
            }

            // Auto-scan when redact tool is selected
            if tool == .redact && state.hasImage {
              state.startRedact()
            }
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
          ColorPicker("", selection: $state.strokeColor)
            .labelsHidden()
            .onChange(of: state.strokeColor) {
              if let id = state.selectedAnnotationId {
                state.updateAnnotationProperties(id: id, strokeColor: state.strokeColor)
              }
            }
            .onAppear {
              // Use KVO to detect when the system color panel becomes visible
              colorPanelObservation = NSColorPanel.shared.observe(\.isVisible, options: [.new]) { _, change in
                if change.newValue == true {
                  Task { @MainActor in
                    let colorPanel = NSColorPanel.shared
                    // Hide instantly to prevent flash at old position
                    colorPanel.alphaValue = 0
                    // Wait for system to finish its layout
                    try? await Task.sleep(for: .milliseconds(50))
                    // Reposition to near the editor
                    repositionColorPanel()
                    // Fade in at the correct position
                    NSAnimationContext.beginGrouping()
                    NSAnimationContext.current.duration = 0.15
                    colorPanel.animator().alphaValue = 1
                    NSAnimationContext.endGrouping()
                  }
                }
              }
            }
        }

        // Quick colors
        HStack(spacing: 6) {
          ForEach([Color.red, .orange, .yellow, .green, .blue, .purple, .white, .black], id: \.self) { color in
            Circle()
              .fill(color)
              .frame(width: 18, height: 18)
              .overlay(Circle().stroke(.secondary.opacity(0.3), lineWidth: 1))
              .onTapGesture {
                state.strokeColor = color
                // Also update selected annotation in real-time
                if let id = state.selectedAnnotationId {
                  state.updateAnnotationProperties(id: id, strokeColor: color)
                }
              }
          }
        }

        // Stroke width
        VStack(alignment: .leading, spacing: 4) {
          Text("Thickness: \(Int(state.strokeWidth))")
            .font(.caption)
            .foregroundStyle(.secondary)
          Slider(value: $state.strokeWidth, in: 1...20, step: 1)
            .onChange(of: state.strokeWidth) {
              if let id = state.selectedAnnotationId {
                state.updateAnnotationProperties(id: id, strokeWidth: state.strokeWidth)
              }
            }
        }

        // Blur type picker (when blur tool selected)
        if state.selectedTool == .blur {
          VStack(alignment: .leading, spacing: 4) {
            Text("Blur Type")
              .font(.caption)
              .foregroundStyle(.secondary)
            Picker("", selection: $state.blurType) {
              ForEach(BlurType.allCases) { type in
                Label(type.displayName, systemImage: type.icon)
                  .tag(type)
              }
            }
            .pickerStyle(.segmented)
          }
        }

        // Font size slider (when text tool selected or text annotation selected)
        if state.selectedTool == .text || state.selectedTextAnnotation != nil {
          VStack(alignment: .leading, spacing: 4) {
            Text("Font Size: \(Int(fontSizeValue))pt")
              .font(.caption)
              .foregroundStyle(.secondary)
            Slider(value: fontSizeBinding, in: 12...72, step: 1)
          }
        }
      }
      .padding()

      // Text styling section (when text annotation is selected)
      if state.selectedTextAnnotation != nil {
        Divider()
        textStylingSection
          .padding()
      }

      Spacer()

      // Bottom actions
      VStack(spacing: 8) {
        Button(action: { state.clearAll() }) {
          Label("Clear All", systemImage: "trash")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
      .padding()
    }
    .background(.background)
  }

  // MARK: - Font Size

  private var fontSizeValue: CGFloat {
    if let annotation = state.selectedTextAnnotation {
      return annotation.properties.fontSize
    }
    return 16
  }

  private var fontSizeBinding: Binding<CGFloat> {
    Binding(
      get: { fontSizeValue },
      set: { newSize in
        if let id = state.selectedAnnotationId {
          state.updateAnnotationProperties(id: id, fontSize: newSize)
        }
      }
    )
  }

  // MARK: - Text Styling Section

  private var textStylingSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Text Style")
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)

      // Text color
      VStack(alignment: .leading, spacing: 4) {
        Text("Text Color")
          .font(.caption2)
          .foregroundStyle(.secondary)

        HStack(spacing: 4) {
          ForEach([Color.white, .black, .red, .orange, .yellow, .green, .blue], id: \.self) { color in
            Button {
              if let id = state.selectedAnnotationId {
                state.updateAnnotationProperties(id: id, strokeColor: color)
              }
            } label: {
              Circle()
                .fill(color)
                .frame(width: 22, height: 22)
                .overlay(
                  Circle().stroke(
                    isColorSelected(color, for: \.strokeColor) ? Color.accentColor : Color.secondary.opacity(0.4),
                    lineWidth: isColorSelected(color, for: \.strokeColor) ? 2 : 1
                  )
                )
            }
            .buttonStyle(.plain)
          }
        }
      }

      // Background color
      VStack(alignment: .leading, spacing: 4) {
        Text("Background")
          .font(.caption2)
          .foregroundStyle(.secondary)

        HStack(spacing: 4) {
          // None button
          Button {
            if let id = state.selectedAnnotationId {
              state.updateAnnotationProperties(id: id, fillColor: .clear)
            }
          } label: {
            Text("None")
              .font(.system(size: 9))
              .foregroundStyle(.primary)
              .frame(width: 36, height: 22)
              .background(
                RoundedRectangle(cornerRadius: 4)
                  .fill(state.selectedTextAnnotation?.properties.fillColor == .clear
                    ? Color.accentColor.opacity(0.3)
                    : Color.primary.opacity(0.1))
              )
          }
          .buttonStyle(.plain)

          ForEach([Color.white, .black, .yellow, .blue], id: \.self) { color in
            Button {
              if let id = state.selectedAnnotationId {
                state.updateAnnotationProperties(id: id, fillColor: color)
              }
            } label: {
              Circle()
                .fill(color)
                .frame(width: 22, height: 22)
                .overlay(
                  Circle().stroke(
                    isColorSelected(color, for: \.fillColor) ? Color.accentColor : Color.secondary.opacity(0.4),
                    lineWidth: isColorSelected(color, for: \.fillColor) ? 2 : 1
                  )
                )
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  private func isColorSelected(_ color: Color, for keyPath: KeyPath<AnnotationProperties, Color>) -> Bool {
    guard let annotation = state.selectedTextAnnotation else { return false }
    return annotation.properties[keyPath: keyPath] == color
  }

  /// Reposition the system color panel next to the annotation editor window
  private func repositionColorPanel() {
    let colorPanel = NSColorPanel.shared
    guard let editorWindow = NSApp.windows.first(where: { $0.title == "SnapForge Editor" }) else { return }

    let editorFrame = editorWindow.frame
    let panelSize = colorPanel.frame.size

    // Position at the right edge of the editor, near the top where the Color row is
    let idealX = editorFrame.maxX + 8
    // Align the top of the color panel with ~ 40% from top of editor (near Color row)
    let idealY = editorFrame.maxY - panelSize.height - 120

    // Clamp to screen bounds
    if let screen = editorWindow.screen {
      let screenFrame = screen.visibleFrame
      // If no room on the right, try left side
      let finalX: CGFloat
      if idealX + panelSize.width <= screenFrame.maxX {
        finalX = idealX
      } else {
        finalX = editorFrame.minX - panelSize.width - 8
      }
      let clampedX = max(finalX, screenFrame.minX)
      let clampedY = max(min(idealY, screenFrame.maxY - panelSize.height), screenFrame.minY)
      colorPanel.setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
    } else {
      colorPanel.setFrameOrigin(NSPoint(x: idealX, y: idealY))
    }

    // Attach as child window so it moves with the editor
    if !(editorWindow.childWindows?.contains(colorPanel) ?? false) {
      editorWindow.addChildWindow(colorPanel, ordered: .above)
    }
  }
}
