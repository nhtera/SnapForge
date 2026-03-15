import SwiftUI

/// Batch Export sheet — configure format, quality, resize, then export selected captures as ZIP.
struct BatchExportView: View {
  let captures: [HistoryCapture]
  @State private var options = BatchExportOptions()
  @State private var isExporting = false
  @State private var progress: Double = 0
  @State private var currentItem: String = ""
  @State private var exportComplete = false
  @State private var resultURL: URL?
  @State private var errorMessage: String?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 0) {
      // Header
      header
        .padding(16)

      Divider()

      // Settings
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          formatSection
          qualitySection
          resizeSection
        }
        .padding(20)
      }

      Divider()

      // Footer
      footer
        .padding(16)
    }
    .frame(width: 400, height: 480)
    .onChange(of: options.format) { _, _ in resetCompletion() }
    .onChange(of: options.quality) { _, _ in resetCompletion() }
    .onChange(of: options.resizeEnabled) { _, _ in resetCompletion() }
    .onChange(of: options.resizeWidth) { _, _ in resetCompletion() }
    .onChange(of: options.resizeHeight) { _, _ in resetCompletion() }
    .onChange(of: options.maintainAspectRatio) { _, _ in resetCompletion() }
  }

  // MARK: - Header

  private var header: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text("Batch Export")
          .font(.headline)
        Text("\(captures.count) items selected")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button(action: { dismiss() }) {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(.secondary)
          .font(.system(size: 18))
      }
      .buttonStyle(.plain)
    }
  }

  // MARK: - Format

  private var formatSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("FORMAT")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)

      Picker("", selection: $options.format) {
        ForEach(ImageExportFormat.allCases) { fmt in
          Text(fmt.rawValue).tag(fmt)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
    }
  }

  // MARK: - Quality

  private var qualitySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("QUALITY")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.secondary)
        Spacer()
        Text("\(Int(options.quality * 100))%")
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(.secondary)
      }

      Slider(value: $options.quality, in: 0.1...1.0, step: 0.05)

      if options.format == .png {
        Text("PNG is always lossless — quality setting is ignored.")
          .font(.system(size: 10))
          .foregroundStyle(.tertiary)
      }
    }
  }

  // MARK: - Resize

  private var resizeSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Toggle(isOn: $options.resizeEnabled) {
        Text("Resize Images")
          .font(.system(size: 12, weight: .medium))
      }
      .toggleStyle(.switch)
      .controlSize(.small)

      if options.resizeEnabled {
        HStack(spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Max Width")
              .font(.system(size: 10))
              .foregroundStyle(.secondary)
            TextField("", value: $options.resizeWidth, format: .number)
              .textFieldStyle(.roundedBorder)
              .frame(width: 80)
          }

          VStack(alignment: .leading, spacing: 4) {
            Text("Max Height")
              .font(.system(size: 10))
              .foregroundStyle(.secondary)
            TextField("", value: $options.resizeHeight, format: .number)
              .textFieldStyle(.roundedBorder)
              .frame(width: 80)
          }
        }

        Toggle(isOn: $options.maintainAspectRatio) {
          Text("Maintain aspect ratio")
            .font(.system(size: 11))
        }
        .toggleStyle(.checkbox)
        .controlSize(.small)

        Text("Images smaller than the specified size will not be upscaled.")
          .font(.system(size: 10))
          .foregroundStyle(.tertiary)
      }
    }
    .padding(12)
    .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 8))
  }

  // MARK: - Footer

  private var footer: some View {
    VStack(spacing: 12) {
      if isExporting {
        VStack(spacing: 6) {
          ProgressView(value: progress)
            .progressViewStyle(.linear)
          Text(currentItem)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }

      if let errorMessage {
        HStack(spacing: 4) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
          Text(errorMessage)
            .font(.system(size: 11))
            .foregroundStyle(.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      HStack {
        if exportComplete {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
          Text("Export complete!")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.green)

          Spacer()

          Button("Done") { dismiss() }
            .buttonStyle(.borderedProminent)
        } else {
          // Estimated size
          estimatedSize

          Spacer()

          Button("Cancel") { dismiss() }
            .keyboardShortcut(.cancelAction)

          Button("Export ZIP") { startExport() }
            .buttonStyle(.borderedProminent)
            .disabled(isExporting || captures.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
      }
    }
  }

  private var estimatedSize: some View {
    let totalOriginalSize = captures.reduce(0) { $0 + $1.fileSize }
    let formattedSize = ByteCountFormatter.string(fromByteCount: totalOriginalSize, countStyle: .file)
    return Text("Original: \(formattedSize)")
      .font(.system(size: 10))
      .foregroundStyle(.tertiary)
  }

  // MARK: - Export

  private func startExport() {
    isExporting = true
    progress = 0
    currentItem = "Starting…"
    errorMessage = nil

    Task {
      let service = BatchExportService.shared

      // Poll progress in background
      let progressTask = Task {
        while !Task.isCancelled {
          progress = service.progress
          currentItem = service.currentItem
          try? await Task.sleep(for: .milliseconds(100))
        }
      }

      let url = await service.exportBatch(captures: captures, options: options)
      progressTask.cancel()

      progress = 1.0
      isExporting = false

      if let url {
        resultURL = url
        exportComplete = true
        service.saveWithPanel(zipURL: url)
      } else {
        // Show error from service
        errorMessage = service.errorMessage ?? "Export failed — check console for details"
      }
    }
  }

  private func resetCompletion() {
    exportComplete = false
    resultURL = nil
    errorMessage = nil
  }
}
