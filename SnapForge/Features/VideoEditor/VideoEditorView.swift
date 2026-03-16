import SwiftUI
import AVFoundation
import AVKit

/// Main video editor view with player preview, playback controls,
/// timeline with trim handles, and export options.
struct VideoEditorView: View {
    @State var state: VideoEditorState
    @State private var showingSaveOptions = false

    var body: some View {
        VStack(spacing: 0) {
            // Video player preview
            playerSection

            Divider()

            // Controls + Timeline + Export
            VStack(spacing: DesignTokens.Spacing.md) {
                // Playback controls
                VideoControlsView(state: state)

                // Timeline with trim handles
                VideoTimelineView(state: state)

                Divider()

                // Export toolbar
                exportToolbar
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .frame(minWidth: 700, minHeight: 500)
        .task {
            await state.loadVideo()
            await state.extractFrames()
        }
        .overlay {
            if state.isExporting {
                exportProgressOverlay
            }
        }
        .onDisappear {
            state.cleanup()
        }
    }

    // MARK: - Player Section

    private var playerSection: some View {
        VideoPlayer(player: state.player)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
    }

    // MARK: - Export Toolbar

    private var exportToolbar: some View {
        HStack {
            Button("Cancel") {
                AppCoordinator.shared.dismissVideoEditor()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: DesignTokens.Spacing.sm) {
                // Replace Original
                Button(action: { replaceOriginal() }) {
                    Label("Replace Original", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                // Save as Copy
                Button(action: { saveAsCopy() }) {
                    Label("Save Copy", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                // Export Trimmed
                Button(action: { exportTrimmed() }) {
                    Label("Export Trimmed", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.isExporting)
            }
        }
    }

    // MARK: - Export Progress Overlay

    private var exportProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)

            VStack(spacing: DesignTokens.Spacing.md) {
                ProgressView(value: state.exportProgress, total: 1.0)
                    .progressViewStyle(.linear)
                    .frame(width: 200)

                Text("Exporting… \(Int(state.exportProgress * 100))%")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .padding(DesignTokens.Spacing.xl)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        }
    }

    // MARK: - Export Actions

    private func replaceOriginal() {
        state.isExporting = true
        state.exportProgress = 0

        Task {
            do {
                try await VideoEditorExporter.replaceOriginal(state: state) { progress in
                    Task { @MainActor in
                        state.exportProgress = progress
                    }
                }
                state.isExporting = false
                AppCoordinator.shared.dismissVideoEditor()
            } catch {
                state.isExporting = false
                print("❌ Replace original failed: \(error)")
            }
        }
    }

    private func saveAsCopy() {
        state.isExporting = true
        state.exportProgress = 0

        Task {
            do {
                let copyURL = try await VideoEditorExporter.saveAsCopy(state: state) { progress in
                    Task { @MainActor in
                        state.exportProgress = progress
                    }
                }
                state.isExporting = false
                NSWorkspace.shared.activateFileViewerSelecting([copyURL])
                AppCoordinator.shared.dismissVideoEditor()
            } catch {
                state.isExporting = false
                print("❌ Save as copy failed: \(error)")
            }
        }
    }

    private func exportTrimmed() {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Trimmed Video"
        savePanel.nameFieldStringValue = VideoEditorExporter.generateCopyFilename(
            from: state.videoURL
        )
        savePanel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        savePanel.canCreateDirectories = true

        guard savePanel.runModal() == .OK, let outputURL = savePanel.url else { return }

        state.isExporting = true
        state.exportProgress = 0

        Task {
            do {
                try await VideoEditorExporter.exportTrimmed(
                    state: state,
                    to: outputURL
                ) { progress in
                    Task { @MainActor in
                        state.exportProgress = progress
                    }
                }
                state.isExporting = false
                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                AppCoordinator.shared.dismissVideoEditor()
            } catch {
                state.isExporting = false
                print("❌ Export failed: \(error)")
            }
        }
    }
}
