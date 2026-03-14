import SwiftUI

/// Annotation editor view — canvas with tool palette for marking up captured images.
struct AnnotationView: View {
  @State var image: NSImage
  @StateObject private var state = AnnotateState()
  @State private var canvasSize: CGSize = .zero
  @State private var imageRect: CGRect = .zero
  // Crop undo history — stores (image, annotations) snapshots before each crop
  @State private var cropHistory: [(image: NSImage, annotations: [AnnotationItem])] = []
  // Export settings
  @State private var showExportPicker = false
  @State private var exportFormat: ImageExportFormat = .png
  @State private var exportQuality: CGFloat = 0.9

  var body: some View {
    HSplitView {
      // Layers panel (left sidebar, conditionally shown)
      if state.isLayersPanelVisible {
        LayersPanelView(state: state)
      }

      // Canvas area
      GeometryReader { geo in
         ZStack {
          Color(nsColor: .windowBackgroundColor)

          canvasContent(geo: geo)

          // Crop toolbar (bottom bar)
          if state.selectedTool == .crop && state.isCropActive {
            VStack {
              Spacer()
              cropToolbar
                .padding(.bottom, 16)
            }
          }
        }
        .onChange(of: geo.size) { _, newSize in
          canvasSize = newSize
          imageRect = calcImageRect(canvasSize: newSize, imageSize: image.size)
        }
      }

      // Tool palette (right sidebar)
      ToolPaletteView(state: state)
        .frame(width: 220)
    }
    .onAppear {
      state.loadImage(image)
    }
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        Button(action: { performUndo() }) {
          Image(systemName: "arrow.uturn.backward")
        }
        .disabled(!state.canUndo && cropHistory.isEmpty)
        .help("Undo (⌘Z)")
        .keyboardShortcut("z", modifiers: .command)

        Button(action: { state.redo() }) {
          Image(systemName: "arrow.uturn.forward")
        }
        .disabled(!state.canRedo)
        .help("Redo (⌘⇧Z)")
        .keyboardShortcut("z", modifiers: [.command, .shift])

        Button(action: { state.clearAll() }) {
          Image(systemName: "trash")
        }
        .disabled(state.annotations.isEmpty)
        .help("Clear All")

        Divider()

        Button(action: { state.isLayersPanelVisible.toggle() }) {
          Image(systemName: state.isLayersPanelVisible ? "sidebar.leading" : "square.3.layers.3d")
        }
        .help(state.isLayersPanelVisible ? "Hide Layers" : "Show Layers")

        Divider()

        Button("Export") {
          showExportPicker.toggle()
        }
        .buttonStyle(.borderedProminent)
        .popover(isPresented: $showExportPicker) {
          exportFormatPicker
        }
      }
    }
    // Tool keyboard shortcuts (work regardless of focus)
    .background { toolShortcutButtons }
  }

  /// Hidden buttons that register keyboard shortcuts for each tool
  @ViewBuilder
  private var toolShortcutButtons: some View {
    ForEach(AnnotationToolType.allCases) { tool in
      Button("") {
        // Skip if editing text (typing letters)
        guard state.editingTextAnnotationId == nil else { return }
        state.selectedTool = tool
        // Auto-init crop when pressing shortcut
        if tool == .crop && state.hasImage {
          if state.cropRect == nil {
            state.initializeCrop()
          } else {
            state.isCropActive = true
          }
        }
      }
      .keyboardShortcut(KeyEquivalent(tool.defaultShortcut), modifiers: [])
      .hidden()
    }
  }

  // MARK: - Canvas Content

  @ViewBuilder
  private func canvasContent(geo: GeometryProxy) -> some View {
    let imgSize = image.size
    let scale = calcDisplayScale(availableSize: geo.size, imageSize: imgSize)

    ZStack {
      // Image layer
      Image(nsImage: image)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
        .onAppear {
          canvasSize = geo.size
          imageRect = calcImageRect(canvasSize: geo.size, imageSize: image.size)
        }

      // Drawing canvas overlay (NSViewRepresentable)
      CanvasDrawingView(state: state, displayScale: scale)
        .frame(
          width: imgSize.width * scale,
          height: imgSize.height * scale
        )

      // Text editing overlay (same frame as canvas for alignment)
      if state.editingTextAnnotationId != nil {
        TextEditOverlay(
          state: state,
          scale: scale,
          imageSize: CGSize(width: imgSize.width, height: imgSize.height)
        )
        .frame(
          width: imgSize.width * scale,
          height: imgSize.height * scale
        )
      }

      // Crop overlay (dim + handles + grid)
      if state.selectedTool == .crop && state.isCropActive {
        CropOverlayView(
          state: state,
          scale: scale,
          imageSize: CGSize(width: imgSize.width, height: imgSize.height)
        )
        .frame(
          width: imgSize.width * scale,
          height: imgSize.height * scale
        )
      }
    }
  }

  // MARK: - Display Scale Calculation

  private func calcDisplayScale(availableSize: CGSize, imageSize: NSSize) -> CGFloat {
    let padding: CGFloat = 20
    let availableWidth = availableSize.width - padding * 2
    let availableHeight = availableSize.height - padding * 2

    guard imageSize.width > 0, imageSize.height > 0 else { return 1.0 }

    let scaleX = availableWidth / imageSize.width
    let scaleY = availableHeight / imageSize.height
    return min(scaleX, scaleY, 1.0)
  }

  // MARK: - Export Format Picker

  private var exportFormatPicker: some View {
    VStack(spacing: 12) {
      Text("Export Format")
        .font(.headline)

      Picker("Format", selection: $exportFormat) {
        ForEach(ImageExportFormat.allCases) { fmt in
          Text(fmt.rawValue).tag(fmt)
        }
      }
      .pickerStyle(.segmented)

      if exportFormat != .png {
        VStack(alignment: .leading, spacing: 4) {
          Text("Quality: \(Int(exportQuality * 100))%")
            .font(.caption)
            .foregroundStyle(.secondary)
          Slider(value: $exportQuality, in: 0.1...1.0, step: 0.05)
        }
      }

      HStack(spacing: 12) {
        Button("Copy") {
          exportImage(copyOnly: true)
          showExportPicker = false
        }

        Button("Save") {
          exportImage(copyOnly: false)
          showExportPicker = false
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding()
    .frame(width: 260)
  }

  // MARK: - Image Rect Calculation

  private func calcImageRect(canvasSize: CGSize, imageSize: NSSize) -> CGRect {
    let padding: CGFloat = 20
    let availableWidth = canvasSize.width - padding * 2
    let availableHeight = canvasSize.height - padding * 2
    let imageAspect = imageSize.width / imageSize.height
    let availableAspect = availableWidth / availableHeight

    var displayWidth: CGFloat
    var displayHeight: CGFloat

    if imageAspect > availableAspect {
      displayWidth = availableWidth
      displayHeight = availableWidth / imageAspect
    } else {
      displayHeight = availableHeight
      displayWidth = availableHeight * imageAspect
    }

    let x = padding + (availableWidth - displayWidth) / 2
    let y = padding + (availableHeight - displayHeight) / 2
    return CGRect(x: x, y: y, width: displayWidth, height: displayHeight)
  }

  // MARK: - Text Editing
  // Text editing is handled by TextEditOverlay component

  // MARK: - Crop

  private var cropToolbar: some View {
    HStack(spacing: 12) {
      Button(action: { state.cancelCrop() }) {
        Label("Cancel", systemImage: "xmark")
          .font(.system(size: 13, weight: .medium))
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
      }
      .buttonStyle(.plain)
      .keyboardShortcut(.escape, modifiers: [])

      Button(action: { applyCrop() }) {
        Label("Apply Crop", systemImage: "checkmark")
          .font(.system(size: 13, weight: .medium))
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
          .foregroundStyle(.white)
      }
      .buttonStyle(.plain)
      .keyboardShortcut(.return, modifiers: [])
    }
  }

  private func applyCrop() {
    guard let cropRect = state.cropRect else { return }

    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      state.resetCrop()
      return
    }

    let pixelWidth = CGFloat(cgImage.width)
    let pixelHeight = CGFloat(cgImage.height)

    // cropRect is in image coordinates (logical points, bottom-left origin)
    // CGImage uses pixel coordinates (top-left origin)
    let scaleX = pixelWidth / image.size.width
    let scaleY = pixelHeight / image.size.height

    // Convert crop rect from image coords (bottom-left) to pixel coords (top-left)
    let pixelCropX = cropRect.origin.x * scaleX
    // Flip Y: in image coords y=0 is bottom, in CGImage y=0 is top
    let pixelCropY = (image.size.height - cropRect.origin.y - cropRect.height) * scaleY
    let pixelCropW = cropRect.width * scaleX
    let pixelCropH = cropRect.height * scaleY

    let clampedX = max(0, pixelCropX)
    let clampedY = max(0, pixelCropY)
    let clampedW = min(pixelCropW, pixelWidth - clampedX)
    let clampedH = min(pixelCropH, pixelHeight - clampedY)

    guard clampedW > 1, clampedH > 1 else {
      state.resetCrop()
      return
    }

    let cgCropRect = CGRect(x: clampedX, y: clampedY, width: clampedW, height: clampedH)

    guard let croppedCG = cgImage.cropping(to: cgCropRect) else {
      state.resetCrop()
      return
    }

    let backingScale = NSScreen.main?.backingScaleFactor ?? 2.0
    let logicalW = CGFloat(croppedCG.width) / backingScale
    let logicalH = CGFloat(croppedCG.height) / backingScale
    let croppedImage = NSImage(cgImage: croppedCG, size: NSSize(width: logicalW, height: logicalH))

    cropHistory.append((image: image, annotations: state.annotations))

    image = croppedImage
    state.loadImage(croppedImage)
    imageRect = calcImageRect(canvasSize: canvasSize, imageSize: croppedImage.size)
  }

  /// Unified undo
  private func performUndo() {
    if state.canUndo {
      state.undo()
    } else if !cropHistory.isEmpty {
      undoCrop()
    }
  }

  private func undoCrop() {
    guard let previous = cropHistory.popLast() else { return }
    image = previous.image
    state.loadImage(previous.image)
    for annotation in previous.annotations {
      state.annotations.append(annotation)
    }
    imageRect = calcImageRect(canvasSize: canvasSize, imageSize: image.size)
  }

  // MARK: - Export

  private func exportImage(copyOnly: Bool = false) {
    let exportService = ExportService()
    guard let rendered = exportService.renderAnnotatedImage(
      baseImage: image,
      annotations: state.annotations,
      imageSize: image.size
    ) else { return }

    ClipboardService().copyImage(rendered)

    if !copyOnly {
      let storage = StorageService()
      let filename = exportService.generateFilename(format: exportFormat)
      let url = storage.snapForgeDirectory.appendingPathComponent(filename)

      do {
        try exportService.exportImage(rendered, format: exportFormat, quality: exportQuality, to: url)
        NSWorkspace.shared.activateFileViewerSelecting([url])
      } catch {
        print("❌ Export failed: \(error)")
      }
    }
  }
}

// MARK: - Tool Palette

struct ToolPaletteView: View {
  @ObservedObject var state: AnnotateState

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
        }

        // Quick colors
        HStack(spacing: 6) {
          ForEach([Color.red, .orange, .yellow, .green, .blue, .purple, .white, .black], id: \.self) { color in
            Circle()
              .fill(color)
              .frame(width: 18, height: 18)
              .overlay(Circle().stroke(.secondary.opacity(0.3), lineWidth: 1))
              .onTapGesture { state.strokeColor = color }
          }
        }

        // Stroke width
        VStack(alignment: .leading, spacing: 4) {
          Text("Thickness: \(Int(state.strokeWidth))")
            .font(.caption)
            .foregroundStyle(.secondary)
          Slider(value: $state.strokeWidth, in: 1...20, step: 1)
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
              .foregroundColor(.primary)
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
}

// MARK: - Tool Button

struct ToolButton: View {
  let tool: AnnotationToolType
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    VStack(spacing: 3) {
      Image(systemName: tool.icon)
        .font(.system(size: 20))
      Text(tool.displayName)
        .font(.system(size: 9))
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, minHeight: 48)
    .foregroundStyle(isSelected ? Color.accentColor : .primary)
    .background(isSelected ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
    )
    .contentShape(Rectangle())
    .onTapGesture {
      // Resign first responder from canvas so the tap registers immediately
      NSApp.keyWindow?.makeFirstResponder(nil)
      action()
    }
    .help(tool.displayName)
  }
}
