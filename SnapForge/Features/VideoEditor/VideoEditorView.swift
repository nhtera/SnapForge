import SwiftUI
import AVKit

/// Main video editor view with toolbar, sidebars, player, timeline, and export settings.
struct VideoEditorView: View {
    @Bindable var state: VideoEditorState
    @State private var showExportSettings = false
    @State private var showingSaveDialog = false
    @State private var cachedWallpaperImage: NSImage?
    @State private var cachedWallpaperURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            VideoEditorToolbarView(state: state)
            Divider()

            // Main content area
            HStack(spacing: 0) {
                // Left sidebar — Video Details
                if state.isVideoInfoSidebarVisible {
                    VideoEditorDetailsSidebarView(state: state)
                        .frame(width: 240)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Divider()
                }

                // Center — Player + Controls + Timeline + Export
                centerContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Right sidebar — Background (video only)
                if state.isRightSidebarVisible && !state.isGIF {
                    Divider()
                    VideoEditorRightSidebar(state: state)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: state.isVideoInfoSidebarVisible)
            .animation(.easeInOut(duration: 0.25), value: state.isRightSidebarVisible)

            // Bottom bar
            VideoEditorBottomBar(
                isGIF: state.isGIF,
                onCancel: handleCancel,
                onConvert: { showingSaveDialog = true }
            )
        }
        .background(Color(NSColor.windowBackgroundColor))
        .overlay {
            if state.isExporting {
                exportOverlay
            }
        }
        .overlay {
            if showingSaveDialog {
                saveDialogOverlay
            }
        }
        .task {
            await state.loadVideo()
            await state.extractFrames()
        }
        .onAppear {
            updateWallpaperCacheIfNeeded()
        }
        .onChange(of: state.backgroundStyle) {
            updateWallpaperCacheIfNeeded()
        }
        .onDisappear {
            state.cleanup()
        }
    }

    // MARK: - Center Content

    private var centerContent: some View {
        VStack(spacing: 0) {
            // Player / Preview
            playerSection
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Controls + Timeline + Export Settings
            VStack(spacing: DesignTokens.Spacing.md) {
                if state.isGIF {
                    // GIF controls: frame info instead of play/pause
                    GIFControlsView(state: state)

                    // Timeline with frame-index trim handles
                    GIFTimelineView(state: state)

                    // GIF export settings (dimensions + info)
                    GIFExportSettingsPanel(state: state)
                } else {
                    // Playback controls
                    VideoControlsView(state: state)

                    // Timeline
                    VideoTimelineView(state: state)

                    // Expand/collapse export settings — entire row is clickable
                    VStack(spacing: 0) {
                        Button {
                            withAnimation(DesignTokens.Animation.fast) {
                                showExportSettings.toggle()
                            }
                        } label: {
                            HStack(spacing: DesignTokens.Spacing.xs) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .rotationEffect(.degrees(showExportSettings ? 90 : 0))
                                Image(systemName: "gearshape")
                                    .font(.system(size: 11))
                                Text("Export Settings")
                                    .font(.system(size: 12, weight: .medium))
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        if showExportSettings {
                            VideoEditorExportSettingsPanel(state: state)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
            }
            .padding(DesignTokens.Spacing.md)
        }
    }

    // MARK: - Player Section

    private var playerSection: some View {
        GeometryReader { geo in
            if state.isGIF {
                gifPreviewSection(in: geo.size)
            } else {
                let hasBackground = state.backgroundStyle != .none && state.backgroundPadding > 0
                let hasValidSize = state.naturalSize.width > 0 && state.naturalSize.height > 0

                if hasValidSize && hasBackground {
                    backgroundPlayerView(in: geo.size)
                } else {
                    plainPlayerView(in: geo.size)
                }
            }
        }
    }

    private func gifPreviewSection(in containerSize: CGSize) -> some View {
        ZStack {
            Color.black.opacity(0.3)
            GIFPreviewView(url: state.videoURL)
                .frame(maxWidth: containerSize.width, maxHeight: containerSize.height)
        }
        .frame(width: containerSize.width, height: containerSize.height)
    }

    private func backgroundPlayerView(in containerSize: CGSize) -> some View {
        let videoW = max(1, state.naturalSize.width)
        let videoH = max(1, state.naturalSize.height)

        // Calculate the exact output frame ratio: (video + 2*padding) on each axis
        let outputW = videoW + state.backgroundPadding * 2
        let outputH = videoH + state.backgroundPadding * 2
        let outputAspect = outputW / outputH

        // Fit the output frame into the container
        let frameW: CGFloat
        let frameH: CGFloat
        if containerSize.width / containerSize.height > outputAspect {
            frameH = containerSize.height
            frameW = frameH * outputAspect
        } else {
            frameW = containerSize.width
            frameH = frameW / outputAspect
        }

        // Video size within the frame (proportional to padding ratio)
        let scale = frameW / outputW
        let playerW = videoW * scale
        let playerH = videoH * scale
        let scaledCornerRadius = state.backgroundCornerRadius * scale
        let shadowScale = min(frameW, frameH) / 800

        return ZStack {
            backgroundFill
                .frame(width: frameW, height: frameH)
                .clipped()
                .drawingGroup() // GPU-accelerated compositing for wallpaper images
                .allowsHitTesting(false) // Prevent wallpaper .fill overflow from stealing clicks

            PlayerViewRepresentable(player: state.player)
                .frame(width: playerW, height: playerH)
                .clipShape(RoundedRectangle(cornerRadius: scaledCornerRadius))
                .shadow(
                    color: .black.opacity(Double(state.backgroundShadowIntensity) * 0.8),
                    radius: CGFloat(state.backgroundShadowIntensity) * 40 * shadowScale
                )
        }
        .frame(width: frameW, height: frameH)
        .clipped() // Ensure ZStack contents don't overflow
        .allowsHitTesting(false) // Player section needs no mouse events
        .frame(width: containerSize.width, height: containerSize.height)
    }

    private func plainPlayerView(in containerSize: CGSize) -> some View {
        let videoW = state.naturalSize.width
        let videoH = state.naturalSize.height

        let fitW: CGFloat
        let fitH: CGFloat
        if videoW > 0 && videoH > 0 {
            let videoAspect = videoW / videoH
            if containerSize.width / containerSize.height > videoAspect {
                fitH = containerSize.height
                fitW = fitH * videoAspect
            } else {
                fitW = containerSize.width
                fitH = fitW / videoAspect
            }
        } else {
            // Before metadata loads, fill the container so the player has non-zero bounds
            fitW = containerSize.width
            fitH = containerSize.height
        }

        return ZStack {
            Color.black.opacity(0.3)

            PlayerViewRepresentable(player: state.player)
                .frame(width: fitW, height: fitH)
        }
        .frame(width: containerSize.width, height: containerSize.height)
    }

    @ViewBuilder
    private var backgroundFill: some View {
        switch state.backgroundStyle {
        case .none:
            EmptyView()
        case .gradient(let preset):
            preset.gradient
        case .solidColor(let color):
            color
        case .wallpaper:
            // Use cached image to avoid reloading from disk on every slider drag
            if let image = cachedWallpaperImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.black
            }
        }
    }

    /// Update wallpaper cache when the background style changes to a wallpaper URL
    private func updateWallpaperCacheIfNeeded() {
        guard case .wallpaper(let url) = state.backgroundStyle else {
            cachedWallpaperImage = nil
            cachedWallpaperURL = nil
            return
        }
        guard url != cachedWallpaperURL else { return }
        cachedWallpaperURL = url
        cachedWallpaperImage = NSImage(contentsOf: url)
    }

    // MARK: - Export Overlay

    private var exportOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: DesignTokens.Spacing.lg) {
                ProgressView(value: state.exportProgress) {
                    Text(state.exportStatusMessage)
                        .font(.headline)
                }
                .frame(width: 300)
                .tint(.accentColor)

                Text("\(Int(state.exportProgress * 100))%")
                    .font(.system(.title, design: .monospaced))
                    .fontWeight(.bold)
            }
            .padding(DesignTokens.Spacing.xxl)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        }
    }

    // MARK: - Save Dialog

    private var saveDialogOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { showingSaveDialog = false }

            VStack(spacing: 0) {
                // App icon
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 56, height: 56)
                        .padding(.top, DesignTokens.Spacing.xl)
                        .padding(.bottom, DesignTokens.Spacing.md)
                }

                // Title
                Text(state.isGIF ? "Save Edited GIF" : "Save Edited Video")
                    .font(.system(size: 15, weight: .bold))
                    .padding(.bottom, DesignTokens.Spacing.xs)

                // Message
                Text(state.isGIF
                    ? "How would you like to save the edited GIF\n\"\(state.filename)\"?"
                    : "How would you like to save the edited video\n\"\(state.filename)\"?")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, DesignTokens.Spacing.xl)
                    .padding(.bottom, DesignTokens.Spacing.xl)

                // Buttons
                VStack(spacing: DesignTokens.Spacing.sm) {
                    // Replace Original
                    Button {
                        showingSaveDialog = false
                        exportReplaceOriginal()
                    } label: {
                        Text("Replace Original")
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DesignTokens.Spacing.sm)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    // Save as Copy
                    Button {
                        showingSaveDialog = false
                        exportSaveAsCopy()
                    } label: {
                        Text("Save as Copy")
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DesignTokens.Spacing.sm)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    // Cancel
                    Button {
                        showingSaveDialog = false
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DesignTokens.Spacing.sm)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.horizontal, DesignTokens.Spacing.xl)
                .padding(.bottom, DesignTokens.Spacing.xl)
            }
            .frame(width: 280)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            .shadow(radius: 20, y: 8)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.15), value: showingSaveDialog)
    }

    // MARK: - Export Actions

    /// Export and replace the original file
    private func exportReplaceOriginal() {
        let originalURL = state.videoURL
        let tempURL = originalURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).\(state.fileExtension)")

        runExport(to: tempURL) {
            // Atomically replace the original file with the exported one
            do {
                _ = try FileManager.default.replaceItemAt(originalURL, withItemAt: tempURL)
                NSWorkspace.shared.activateFileViewerSelecting([originalURL])
            } catch {
                print("❌ Failed to replace original: \(error)")
                // If replace fails, keep the temp file
                NSWorkspace.shared.activateFileViewerSelecting([tempURL])
            }
        }
    }

    /// Export as a new copy via save panel
    private func exportSaveAsCopy() {
        let savePanel = NSSavePanel()
        savePanel.title = "Save as Copy"
        let baseName = state.videoURL.deletingPathExtension().lastPathComponent

        if state.isGIF {
            savePanel.nameFieldStringValue = "\(baseName)_edited.gif"
            savePanel.allowedContentTypes = [.gif]
        } else {
            savePanel.nameFieldStringValue = "\(baseName)_edited.\(state.fileExtension)"
            savePanel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        }
        savePanel.canCreateDirectories = true

        guard savePanel.runModal() == .OK, let outputURL = savePanel.url else { return }

        runExport(to: outputURL) {
            NSWorkspace.shared.activateFileViewerSelecting([outputURL])
        }
    }

    /// Shared export logic
    private func runExport(to outputURL: URL, onSuccess: @escaping () -> Void) {
        Task {
            state.pause()
            state.isExporting = true
            state.exportProgress = 0
            state.exportStatusMessage = state.isGIF ? "Exporting GIF..." : "Exporting video..."

            // Ensure sandbox file access for source video during export + post-export file ops
            let access = SandboxFileAccessManager.shared.beginAccessingURL(state.videoURL)
            defer { access.stop() }

            do {
                try await VideoEditorExporter.exportTrimmed(
                    state: state,
                    to: outputURL
                ) { progress in
                    Task { @MainActor in
                        state.exportProgress = progress
                    }
                }
                state.exportStatusMessage = "Complete!"
                state.isExporting = false
                state.markAsSaved()

                onSuccess()
            } catch {
                print("❌ Export failed: \(error)")
                state.exportStatusMessage = "Export failed"
                try? await Task.sleep(for: .seconds(2))
                state.isExporting = false
            }
        }
    }

    private func handleCancel() {
        AppCoordinator.shared.dismissVideoEditor()
    }
}

// MARK: - Player View (No Native Controls)

/// Custom AVPlayerView that refuses first responder to prevent stealing keyboard
/// focus from toolbar buttons and other controls.
private final class NonFirstResponderPlayerView: AVPlayerView {
    override var acceptsFirstResponder: Bool { false }
    override var canBecomeKeyView: Bool { false }
}

/// Wraps AVPlayerView with controlsStyle = .none and no first-responder behavior
/// to prevent native controls from stealing mouse/keyboard events from toolbar buttons.
private struct PlayerViewRepresentable: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context: Context) -> NonFirstResponderPlayerView {
        let view = NonFirstResponderPlayerView()
        view.controlsStyle = .none
        view.player = player
        view.showsFullScreenToggleButton = false
        return view
    }

    func updateNSView(_ nsView: NonFirstResponderPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
