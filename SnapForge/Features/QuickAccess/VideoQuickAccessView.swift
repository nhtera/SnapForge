import SwiftUI
import AVFoundation

/// Quick Access Overlay for video recordings — appears after recording stops.
/// Provides quick actions: Copy, Trim, Save, View, GIF, Share, Delete.
struct VideoQuickAccessView: View {
    let videoURL: URL
    @State private var thumbnail: NSImage?
    @State private var isHovering = false
    @State private var autoCloseTask: Task<Void, Never>?
    @State private var hoveredAction: VideoQuickAction?
    @State private var videoDuration: String = ""
    @State private var videoFileSize: String = ""
    @State private var closeHovered = false
    @State private var dragHovered = false
    @State private var isConvertingGIF = false

    // Row split: 4 actions per row
    private let row1Actions: [VideoQuickAction] = [.copy, .trim, .save, .view]

    /// GIF conversion is hidden when the file is already a GIF (it would overwrite its own input).
    private var row2Actions: [VideoQuickAction] {
        isGIFFile ? [.share, .delete] : [.gifConvert, .share, .delete]
    }

    private var isGIFFile: Bool {
        videoURL.pathExtension.lowercased() == "gif"
    }

    var body: some View {
        VStack(spacing: 0) {
            videoPreview

            actionToolbar
        }
        .frame(width: 240)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
        )
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.16), radius: 12, x: 0, y: 6)
        .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
        .overlay(alignment: .topLeading) {
            closeButton
        }
        .padding(24)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
        .onAppear {
            extractThumbnailAndMetadata()
            startAutoCloseTimerIfNeeded()
        }
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                autoCloseTask?.cancel()
            } else {
                startAutoCloseTimerIfNeeded()
            }
        }
        .onDisappear {
            autoCloseTask?.cancel()
        }
    }

    // MARK: - Close Button

    @ViewBuilder
    private var closeButton: some View {
        if isHovering {
            Button {
                AppCoordinator.shared.dismissVideoQuickAccess()
            } label: {
                Circle()
                    .fill(closeHovered ? Color.gray.opacity(0.5) : Color.gray.opacity(0.3))
                    .frame(width: 25, height: 25)
                    .overlay {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .onHover { hovered in closeHovered = hovered }
            .padding(8)
            .transition(.opacity)
            .help("Close")
        }
    }

    // MARK: - Video Preview

    private var videoPreview: some View {
        ZStack {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay { gradientScrim }
                    .overlay { playIconOverlay }
                    .overlay(alignment: .bottomTrailing) { durationBadge }
                    .overlay(alignment: .bottomLeading) { fileSizeBadge }
                    .overlay(alignment: .topTrailing) { videoDragHandleOverlay }
                    .overlay { gifConvertingOverlay }
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 140)
                    .overlay {
                        ProgressView().scaleEffect(0.7)
                    }
            }
        }
    }

    @ViewBuilder
    private var gradientScrim: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(0.3), .clear],
                startPoint: .top, endPoint: .bottom
            ).frame(height: 40)
            Spacer()
            LinearGradient(
                colors: [.clear, .black.opacity(0.4)],
                startPoint: .top, endPoint: .bottom
            ).frame(height: 40)
        }
    }

    private var playIconOverlay: some View {
        Circle()
            .fill(.black.opacity(0.35))
            .frame(width: 48, height: 48)
            .overlay {
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .offset(x: 1.5)
            }
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
    }

    @ViewBuilder
    private var durationBadge: some View {
        if !videoDuration.isEmpty {
            Text(videoDuration)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                .padding(8)
        }
    }

    @ViewBuilder
    private var fileSizeBadge: some View {
        if !videoFileSize.isEmpty {
            Text(videoFileSize)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                .padding(8)
        }
    }

    @ViewBuilder
    private var gifConvertingOverlay: some View {
        if isConvertingGIF {
            ZStack {
                Color.black.opacity(0.5)
                VStack(spacing: 6) {
                    ProgressView().scaleEffect(0.8)
                    Text("Converting...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    // MARK: - Drag Handle

    @ViewBuilder
    private var videoDragHandleOverlay: some View {
        if isHovering, let thumbnail {
            FileDragSource(
                fileURL: videoURL,
                dragImage: thumbnail,
                onDragEnded: { success in
                    if success,
                       UserDefaults.standard.bool(forKey: SettingsKey.quickAccessCloseAfterDrag)
                    {
                        Task { @MainActor in
                            AppCoordinator.shared.dismissVideoQuickAccess()
                        }
                    }
                }
            )
            .frame(width: 25, height: 25)
            .overlay {
                Image(systemName: "square.and.arrow.up.on.square")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .allowsHitTesting(false)
            }
            .background(.black.opacity(dragHovered ? 0.5 : 0.3), in: RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            .onHover { hovered in dragHovered = hovered }
            .padding(8)
            .transition(.opacity)
            .help("Drag to app")
        }
    }

    // MARK: - Action Toolbar (2 rows)

    private var actionToolbar: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                ForEach(row1Actions) { action in
                    quickActionButton(action)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 2)

            HStack(spacing: 4) {
                ForEach(row2Actions) { action in
                    quickActionButton(action)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            .padding(.top, 2)
        }
    }

    // MARK: - Action Button

    private func quickActionButton(_ action: VideoQuickAction) -> some View {
        let isActive = hoveredAction == action

        return Button {
            performAction(action)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: action.icon)
                    .font(.system(size: 15, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 24, height: 20)

                Text(action.label)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .foregroundStyle(isActive ? .white : .primary.opacity(0.75))
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? Color.accentColor : .white.opacity(0.05))
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredAction = hovering ? action : nil
            }
        }
        .help(action.tooltip)
    }

    // MARK: - Actions

    private func performAction(_ action: VideoQuickAction) {
        switch action {
        case .copy:
            copyVideoToClipboard()
        case .trim:
            AppCoordinator.shared.dismissVideoQuickAccess()
            AppCoordinator.shared.showVideoEditor(for: videoURL)
        case .save:
            saveVideoAs()
        case .view:
            NSWorkspace.shared.activateFileViewerSelecting([videoURL])
            AppCoordinator.shared.dismissVideoQuickAccess()
        case .gifConvert:
            convertToGIF()
        case .share:
            shareVideo()
        case .delete:
            deleteVideo()
        }
    }

    // MARK: - Helpers

    private func extractThumbnailAndMetadata() {
        Task {
            let access = SandboxFileAccessManager.shared.beginAccessingURL(videoURL)
            defer { access.stop() }

            // File size (cheap attribute read, needs sandbox access)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: videoURL.path),
               let size = attrs[.size] as? Int64 {
                videoFileSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            }

            if videoURL.pathExtension.lowercased() == "gif" {
                if let image = NSImage(contentsOf: videoURL) {
                    thumbnail = image
                }
                return
            }

            let asset = AVURLAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 480, height: 280)

            do {
                let (cgImage, _) = try await generator.image(
                    at: CMTime(seconds: 0.5, preferredTimescale: 600)
                )
                thumbnail = NSImage(
                    cgImage: cgImage,
                    size: NSSize(width: cgImage.width, height: cgImage.height)
                )

                let dur = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(dur)
                let mins = Int(seconds) / 60
                let secs = Int(seconds) % 60
                videoDuration = String(format: "%d:%02d", mins, secs)
            } catch {
                print("⚠️ Failed to extract video thumbnail: \(error)")
            }
        }
    }

    private func copyVideoToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([videoURL as NSURL])
        print("✅ Video file copied to clipboard: \(videoURL.lastPathComponent)")
        AppCoordinator.shared.dismissVideoQuickAccess()
    }

    private func saveVideoAs() {
        let savePanel = NSSavePanel()
        savePanel.title = "Save Recording"
        savePanel.nameFieldStringValue = videoURL.lastPathComponent
        savePanel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        savePanel.canCreateDirectories = true

        guard savePanel.runModal() == .OK, let destinationURL = savePanel.url else { return }

        let access = SandboxFileAccessManager.shared.beginAccessingURL(videoURL)
        defer { access.stop() }

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: videoURL, to: destinationURL)
            print("✅ Video saved to: \(destinationURL.path)")
        } catch {
            print("❌ Failed to save video: \(error)")
        }
        AppCoordinator.shared.dismissVideoQuickAccess()
    }

    private func convertToGIF() {
        guard !isConvertingGIF, !isGIFFile else { return }
        isConvertingGIF = true
        Task { @MainActor in
            let access = SandboxFileAccessManager.shared.beginAccessingURL(videoURL)
            defer { access.stop() }

            // Keep the original recording — the user only asked for an extra GIF copy
            let converter = RecordingGIFConverter()
            let gifURL = await converter.convert(videoURL: videoURL, deleteSource: false)
            isConvertingGIF = false
            if let gifURL {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([gifURL as NSURL])
                print("✅ GIF converted and copied to clipboard: \(gifURL.lastPathComponent)")
            }
            AppCoordinator.shared.dismissVideoQuickAccess()
        }
    }

    private func shareVideo() {
        // Anchor the picker to this Quick Access panel (not whichever app window happens to be visible)
        guard let contentView = AppCoordinator.shared.videoQuickAccessContentView else { return }
        let picker = NSSharingServicePicker(items: [videoURL])
        picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
    }

    private func deleteVideo() {
        let access = SandboxFileAccessManager.shared.beginAccessingURL(videoURL)
        defer { access.stop() }

        do {
            try FileManager.default.trashItem(at: videoURL, resultingItemURL: nil)
            print("✅ Video moved to trash: \(videoURL.lastPathComponent)")
        } catch {
            print("❌ Failed to trash video: \(error)")
        }
        AppCoordinator.shared.dismissVideoQuickAccess()
    }

    private func startAutoCloseTimerIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: SettingsKey.quickAccessAutoClose) else { return }
        let timeout = defaults.double(forKey: SettingsKey.quickAccessTimeout)
        let delay = timeout > 0 ? timeout : 5.0

        autoCloseTask?.cancel()
        autoCloseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            AppCoordinator.shared.dismissVideoQuickAccess()
        }
    }
}

// MARK: - Video Quick Action Model

enum VideoQuickAction: String, CaseIterable, Identifiable {
    case copy, trim, save, view, gifConvert, share, delete

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .copy: "doc.on.clipboard"
        case .trim: "scissors"
        case .save: "square.and.arrow.down"
        case .view: "eye"
        case .gifConvert: "photo.stack"
        case .share: "square.and.arrow.up"
        case .delete: "trash"
        }
    }

    var label: String {
        switch self {
        case .copy: "Copy"
        case .trim: "Trim"
        case .save: "Save"
        case .view: "View"
        case .gifConvert: NSLocalizedString("quick_access.gif", comment: "")
        case .share: NSLocalizedString("quick_access.share", comment: "")
        case .delete: NSLocalizedString("quick_access.delete", comment: "")
        }
    }

    var tooltip: String {
        switch self {
        case .copy: "Copy video file to clipboard"
        case .trim: "Open video trimmer"
        case .save: "Save to another location"
        case .view: "Reveal in Finder"
        case .gifConvert: "Convert to animated GIF"
        case .share: "Share video"
        case .delete: "Move to Trash"
        }
    }
}
