import SwiftUI

/// Annotation editor view — canvas with tool palette for marking up captured images.
struct AnnotationView: View {
  @State private var image: NSImage
  @State private var state = AnnotateState()
  @State private var canvasSize: CGSize = .zero
  @State private var imageRect: CGRect = .zero
  // Crop undo history — stores (image, annotations) snapshots before each crop
  @State private var cropHistory: [(image: NSImage, annotations: [AnnotationItem])] = []
  // Export settings
  @State private var showExportPicker = false
  @State private var exportFormat: ImageExportFormat = .png
  @State private var exportQuality: CGFloat = 0.9
  @State private var showTemplates = false

  init(image: NSImage) {
    _image = State(initialValue: image)
  }

  var body: some View {
    HSplitView {
      // Layers panel (left sidebar, conditionally shown)
      if state.isLayersPanelVisible {
        LayersPanelView(state: state)
      }

      // Sticker library (left sidebar, conditionally shown)
      if state.isStickerLibraryVisible {
        StickerLibraryView(state: state)
      }

      // Canvas area
      GeometryReader { geo in
         ZStack {
          Color(nsColor: .windowBackgroundColor)
            .allowsHitTesting(false)

          canvasContent(geo: geo)

          // Crop toolbar (bottom bar)
          if state.selectedTool == .crop && state.isCropActive {
            VStack {
              Spacer()
              cropToolbar
                .padding(.bottom, 16)
            }
          }

          // Redact overlay
          if state.selectedTool == .redact {
            if state.isRedactScanning {
              VStack(spacing: 12) {
                ProgressView()
                  .controlSize(.large)
                Text("Scanning for sensitive content…")
                  .font(.system(size: 13, weight: .medium))
                  .foregroundStyle(.secondary)
              }
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .background(.ultraThinMaterial)
            } else if !state.redactRegions.isEmpty {
              let scale = imageRect.width / image.size.width
              RedactOverlayView(
                state: state,
                scale: scale,
                imageSize: image.size
              )
              .position(x: imageRect.midX, y: imageRect.midY)
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

        Button(action: { state.isStickerLibraryVisible.toggle() }) {
          Image(systemName: state.isStickerLibraryVisible ? "face.smiling.inverse" : "face.smiling")
        }
        .help(state.isStickerLibraryVisible ? "Hide Stickers" : "Show Stickers")

        Divider()

        Button(action: { showTemplates.toggle() }) {
          Image(systemName: "doc.on.doc")
        }
        .help("Templates")
        .popover(isPresented: $showTemplates) {
          TemplatePopoverView(state: state)
        }

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
      // Image layer (non-interactive — events pass through to canvas)
      Image(nsImage: image)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
        .allowsHitTesting(false)
        .onAppear {
          canvasSize = geo.size
          imageRect = calcImageRect(canvasSize: geo.size, imageSize: image.size)
        }

      // Drawing canvas overlay (NSViewRepresentable)
      CanvasDrawingView(state: state, displayScale: scale, revision: state.revision)
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

    // Update source image WITHOUT clearing annotations
    // (state.loadImage() would clear all annotations)
    state.sourceImage = croppedImage
    state.cropRect = nil
    state.isCropActive = false
    state.hasUnsavedChanges = true

    // Translate annotations: shift by crop offset (bottom-left origin)
    // cropRect origin is in image coords (bottom-left)
    let offsetX = cropRect.origin.x
    let offsetY = cropRect.origin.y
    let cropW = cropRect.width
    let cropH = cropRect.height

    state.annotations = state.annotations.compactMap { annotation in
      var item = annotation
      var bounds = item.bounds

      // Shift annotation by crop offset
      bounds.origin.x -= offsetX
      bounds.origin.y -= offsetY

      // Skip annotations completely outside the crop area
      guard bounds.maxX > 0, bounds.maxY > 0,
            bounds.origin.x < cropW, bounds.origin.y < cropH else {
        return nil
      }

      item.bounds = bounds
      return item
    }

    // Clear undo/redo since we changed the coordinate system
    state.clearUndoHistory()
    state.bumpRevision()

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
    state.bumpRevision()
    imageRect = calcImageRect(canvasSize: canvasSize, imageSize: image.size)
  }

  // MARK: - Export

  private func exportImage(copyOnly: Bool = false) {
    let env = AppEnvironment.shared
    // Filter out hidden annotations so they don't appear in the export
    let visibleAnnotations = state.annotations.filter { !state.hiddenAnnotationIds.contains($0.id) }
    guard let rendered = env.exportService.renderAnnotatedImage(
      baseImage: image,
      annotations: visibleAnnotations,
      imageSize: image.size
    ) else { return }

    env.clipboardService.copyImage(rendered)

    if !copyOnly {
      let filename = env.exportService.generateFilename(format: exportFormat)
      let url = env.storageService.snapForgeDirectory.appendingPathComponent(filename)

      do {
        try env.exportService.exportImage(rendered, format: exportFormat, quality: exportQuality, to: url)
        NSWorkspace.shared.activateFileViewerSelecting([url])
      } catch {
        print("❌ Export failed: \(error)")
      }
    }
  }
}
