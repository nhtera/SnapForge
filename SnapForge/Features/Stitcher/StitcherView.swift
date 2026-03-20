import SwiftUI

/// Stitcher view — arrange multiple screenshots and stitch them into a single image.
struct StitcherView: View {
  @State private var images: [NSImage]
  @State private var config = StitchConfiguration()
  @State private var previewImage: NSImage?
  @State private var showExportPicker = false
  @State private var exportFormat: ImageExportFormat = .png
  @State private var exportQuality: CGFloat = 0.9
  @State private var zoomScale: CGFloat = 1.0
  @State private var localBackgroundColor = Color(nsColor: .windowBackgroundColor)
  @State private var previewContainerSize: CGSize = CGSize(width: 500, height: 450)

  init(images: [NSImage]) {
    _images = State(initialValue: images)
  }

  private let zoomRange: ClosedRange<CGFloat> = 0.1...3.0

  var body: some View {
    HSplitView {
      // Left: Image list
      imageListPanel
        .frame(minWidth: 180, maxWidth: 240)

      // Center: Preview with zoom
      previewPanel
        .frame(minWidth: 400)

      // Right: Settings
      settingsPanel
        .frame(width: 240)
    }
    .onAppear {
      updatePreview()
      fitToView()
    }
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        Button(action: { addImages() }) {
          Image(systemName: "plus")
        }
        .help("Add Images")

        Button("Export") {
          showExportPicker.toggle()
        }
        .buttonStyle(.borderedProminent)
        .popover(isPresented: $showExportPicker) {
          exportPopover
        }
      }
    }
  }

  // MARK: - Image List

  private var imageListPanel: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Images")
          .font(.headline)
        Spacer()
        Text("\(images.count)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(.quaternary, in: Capsule())
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)

      Divider()

      List {
        ForEach(Array(images.enumerated()), id: \.offset) { index, image in
          HStack(spacing: 8) {
            Image(nsImage: image)
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(width: 48, height: 36)
              .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))

            VStack(alignment: .leading, spacing: 2) {
              Text("Image \(index + 1)")
                .font(.system(size: 11, weight: .medium))
              Text("\(Int(image.size.width))×\(Int(image.size.height))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            }

            Spacer()

            if images.count > 2 {
              Button(action: {
                images.remove(at: index)
                updatePreview()
              }) {
                Image(systemName: "xmark.circle.fill")
                  .foregroundStyle(.secondary)
                  .font(.system(size: 12))
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.vertical, 2)
        }
        .onMove { source, destination in
          images.move(fromOffsets: source, toOffset: destination)
          updatePreview()
        }
      }
      .listStyle(.sidebar)
      .scrollContentBackground(.hidden)
    }
    .background(Color(nsColor: .controlBackgroundColor))
  }

  // MARK: - Preview

  private var previewPanel: some View {
    GeometryReader { geo in
      ZStack {
        // Checkerboard background to show transparency
        Color(nsColor: .windowBackgroundColor)
          .onAppear { previewContainerSize = geo.size }
          .onChange(of: geo.size) { _, newSize in previewContainerSize = newSize }

        if let preview = previewImage {
          ScrollView([.horizontal, .vertical]) {
            Image(nsImage: preview)
              .resizable()
              .frame(
                width: preview.size.width * zoomScale,
                height: preview.size.height * zoomScale
              )
              .padding(24)
              .frame(
                minWidth: geo.size.width,
                minHeight: geo.size.height
              )
          }
        } else {
          VStack(spacing: 8) {
            ProgressView()
            Text("Generating preview…")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        // Zoom controls overlay — bottom-right
        VStack {
          Spacer()
          HStack {
            Spacer()
            zoomControls
              .padding(12)
          }
        }
      }
      .onChange(of: geo.size) {
        if zoomScale == 1.0 { fitToView() }
      }
    }
  }

  private var zoomControls: some View {
    HStack(spacing: 6) {
      Button(action: { zoomOut() }) {
        Image(systemName: "minus")
          .font(.system(size: 11, weight: .medium))
          .frame(width: 24, height: 24)
      }
      .buttonStyle(.plain)

      Text("\(Int(zoomScale * 100))%")
        .font(.system(size: 10, design: .monospaced))
        .frame(width: 40)

      Button(action: { zoomIn() }) {
        Image(systemName: "plus")
          .font(.system(size: 11, weight: .medium))
          .frame(width: 24, height: 24)
      }
      .buttonStyle(.plain)

      Divider().frame(height: 16)

      Button(action: { fitToView() }) {
        Image(systemName: "arrow.down.right.and.arrow.up.left")
          .font(.system(size: 11))
          .frame(width: 24, height: 24)
      }
      .buttonStyle(.plain)
      .help("Fit to View")

      Button(action: { zoomScale = 1.0 }) {
        Text("1:1")
          .font(.system(size: 10, weight: .medium))
          .frame(width: 24, height: 24)
      }
      .buttonStyle(.plain)
      .help("Actual Size")
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
  }

  // MARK: - Settings

  private var settingsPanel: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        // Layout picker
        VStack(alignment: .leading, spacing: 8) {
          Text("Layout")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)

          Picker("", selection: $config.layout) {
            ForEach(StitchLayout.allCases) { layout in
              Text(layout.displayName).tag(layout)
            }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .onChange(of: config.layout) { updatePreview() }
        }

        // Alignment picker
        VStack(alignment: .leading, spacing: 8) {
          Text("Alignment")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)

          Picker("", selection: $config.alignment) {
            ForEach(StitchAlignment.allCases) { alignment in
              Text(alignment.displayName).tag(alignment)
            }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .onChange(of: config.alignment) { updatePreview() }
        }

        Divider()

        // Spacing slider
        VStack(alignment: .leading, spacing: 4) {
          Text("Spacing: \(Int(config.spacing)) px")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
          Slider(value: $config.spacing, in: 0...64, step: 2)
            .onChange(of: config.spacing) { updatePreview() }
        }

        // Corner radius
        VStack(alignment: .leading, spacing: 4) {
          Text("Corner Radius: \(Int(config.cornerRadius))")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
          Slider(value: $config.cornerRadius, in: 0...32, step: 2)
            .onChange(of: config.cornerRadius) { updatePreview() }
        }

        Divider()

        // Background color
        VStack(alignment: .leading, spacing: 8) {
          Text("Background")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)

          HStack(spacing: 8) {
            ForEach([NSColor.windowBackgroundColor, .white, .black, .systemGray], id: \.self) { color in
              Circle()
                .fill(Color(nsColor: color))
                .frame(width: 22, height: 22)
                .overlay(
                  Circle().stroke(
                    config.backgroundColor == color ? Color.accentColor : Color.secondary.opacity(0.3),
                    lineWidth: config.backgroundColor == color ? 2 : 1
                  )
                )
                .onTapGesture {
                  config.backgroundColor = color
                  updatePreview()
                }
            }

            Spacer()

            ColorPicker("", selection: $localBackgroundColor)
              .labelsHidden()
              .onChange(of: localBackgroundColor) { _, newValue in
                config.backgroundColor = NSColor(newValue)
                updatePreview()
              }
          }
        }

        Divider()

        // Output info
        if let preview = previewImage {
          VStack(alignment: .leading, spacing: 4) {
            Text("Output")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(.secondary)
              .textCase(.uppercase)
            Text("\(Int(preview.size.width)) × \(Int(preview.size.height)) px")
              .font(.system(size: 12, design: .monospaced))
              .foregroundStyle(.primary)
          }
        }
      }
      .padding(16)
    }
    .background(Color(nsColor: .controlBackgroundColor))
  }

  // MARK: - Export Popover

  private var exportPopover: some View {
    VStack(spacing: 12) {
      Text("Export Stitched Image")
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
          if let preview = previewImage {
            AppEnvironment.shared.clipboardService.copyImage(preview)
          }
          showExportPicker = false
        }

        Button("Save") {
          saveStitchedImage()
          showExportPicker = false
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding()
    .frame(width: 260)
  }

  // MARK: - Zoom Actions

  private func zoomIn() {
    let newScale = min(zoomScale * 1.25, zoomRange.upperBound)
    withAnimation(.easeOut(duration: 0.15)) { zoomScale = newScale }
  }

  private func zoomOut() {
    let newScale = max(zoomScale / 1.25, zoomRange.lowerBound)
    withAnimation(.easeOut(duration: 0.15)) { zoomScale = newScale }
  }

  private func fitToView() {
    guard let preview = previewImage else { return }
    let availableWidth = previewContainerSize.width
    let availableHeight = previewContainerSize.height
    let scaleX = availableWidth / preview.size.width
    let scaleY = availableHeight / preview.size.height
    let fitScale = min(scaleX, scaleY, 1.0)  // Don't upscale
    withAnimation(.easeOut(duration: 0.2)) {
      zoomScale = max(fitScale, zoomRange.lowerBound)
    }
  }

  // MARK: - Actions

  private func updatePreview() {
    previewImage = StitcherService.shared.stitch(images: images, config: config)
  }

  private func addImages() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.png, .jpeg, .heic, .webP]
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    panel.begin { response in
      guard response == .OK else { return }
      let newImages = panel.urls.compactMap { NSImage(contentsOf: $0) }
      Task { @MainActor in
        images.append(contentsOf: newImages)
        updatePreview()
      }
    }
  }

  private func saveStitchedImage() {
    guard let preview = previewImage else { return }
    let exportService = AppEnvironment.shared.exportService
    let storage = AppEnvironment.shared.storageService
    let dir = storage.snapForgeDirectory
    let access = SandboxFileAccessManager.shared.beginAccessingURL(dir)
    defer { access.stop() }
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let filename = exportService.generateFilename(format: exportFormat)
    let url = dir.appendingPathComponent(filename)

    do {
      try exportService.exportImage(preview, format: exportFormat, quality: exportQuality, to: url)
      NSWorkspace.shared.activateFileViewerSelecting([url])
    } catch {
      print("❌ Stitcher export failed: \(error)")
    }
  }
}
