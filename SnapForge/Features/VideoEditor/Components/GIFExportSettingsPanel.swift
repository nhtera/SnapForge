import SwiftUI

/// Export settings panel for GIF files.
/// Shows dimensions picker, GIF metadata info, and file size estimation.
struct GIFExportSettingsPanel: View {
    @Bindable var state: VideoEditorState

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.xl) {
            dimensionsSection

            Divider()
                .frame(height: 80)

            gifInfoSection

            Spacer()

            fileSizeSection
        }
        .padding(DesignTokens.Spacing.md)
    }

    // MARK: - Dimensions

    private var dimensionsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Dimensions")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Picker("", selection: dimensionPresetBinding) {
                ForEach(ExportDimensionPreset.allCases) { preset in
                    // Hide "Custom" for GIF — only percentage presets
                    if preset != .custom {
                        Text(preset.displayLabel(for: state.naturalSize))
                            .tag(preset)
                    }
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 160)
            .controlSize(.small)

            if state.exportSettings.dimensionPreset != .original {
                fileSizeReductionHint
            }
        }
    }

    @ViewBuilder
    private var fileSizeReductionHint: some View {
        let size = state.exportSettings.exportSize(from: state.naturalSize)
        let originalPixels = state.naturalSize.width * state.naturalSize.height
        let newPixels = size.width * size.height
        let reduction = originalPixels > 0 ? Int((1.0 - newPixels / originalPixels) * 100) : 0

        if reduction > 0 {
            Text("~\(reduction)% smaller file size")
                .font(.system(size: 9))
                .foregroundStyle(.green.opacity(0.8))
        }
    }

    // MARK: - GIF Info

    private var gifInfoSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("GIF Info")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                infoRow("Dimensions", "\(Int(state.naturalSize.width)) × \(Int(state.naturalSize.height))")
                infoRow("Frames", "\(state.gifFrameCount)")
                infoRow("Duration", String(format: "%.1fs", state.gifDuration))
                if let meta = state.gifMetadata {
                    infoRow("FPS", String(format: "%.0f", meta.fps))
                }

                // Show trimmed info if trimmed
                if state.gifTrimmedFrameCount < state.gifFrameCount {
                    Divider()
                        .frame(width: 80)
                    HStack(spacing: 4) {
                        Image(systemName: "scissors")
                            .font(.system(size: 8))
                        Text("\(state.gifTrimmedFrameCount) frames (\(String(format: "%.1fs", state.gifTrimmedDuration)))")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.yellow)
                }
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 65, alignment: .leading)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - File Size

    private var fileSizeSection: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("Estimated Size")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            Text(state.formattedEstimatedFileSize)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
        }
    }

    // MARK: - Bindings

    private var dimensionPresetBinding: Binding<ExportDimensionPreset> {
        Binding(
            get: { state.exportSettings.dimensionPreset },
            set: { newValue in
                var settings = state.exportSettings
                settings.dimensionPreset = newValue
                state.updateExportSettings(settings)
            }
        )
    }
}
