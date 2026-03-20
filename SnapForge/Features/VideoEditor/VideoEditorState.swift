import SwiftUI
import AVFoundation
import AVKit



/// Central state management for the SnapForge video editor.
/// Manages video playback, trim range, frame thumbnails, export settings,
/// background customization, undo/redo, and file metadata.
@MainActor
@Observable
final class VideoEditorState {

    // MARK: - Video Source

    let videoURL: URL
    let asset: AVURLAsset
    let player: AVPlayer
    private let playerItem: AVPlayerItem

    // MARK: - GIF Mode

    /// Whether the source file is an animated GIF
    var isGIF: Bool {
        fileExtension == "gif"
    }

    /// GIF metadata (only populated when isGIF)
    private(set) var gifMetadata: GIFMetadata?
    private(set) var gifFrameCount: Int = 0
    private(set) var gifDuration: Double = 0

    /// GIF trim range (frame indices)
    var gifTrimStartFrame: Int = 0
    var gifTrimEndFrame: Int = 0
    private var initialGifTrimStartFrame: Int = 0
    private var initialGifTrimEndFrame: Int = 0
    private var initialGifDimensionPreset: ExportDimensionPreset = .original

    var gifTrimmedFrameCount: Int {
        max(0, gifTrimEndFrame - gifTrimStartFrame + 1)
    }

    /// Duration of trimmed GIF based on per-frame delays
    var gifTrimmedDuration: Double {
        guard let delays = gifMetadata?.frameDelays else { return 0 }
        let start = max(0, gifTrimStartFrame)
        let end = min(delays.count - 1, gifTrimEndFrame)
        guard start <= end else { return 0 }
        return delays[start...end].reduce(0, +)
    }

    // MARK: - Metadata

    private(set) var duration: Double = 0
    private(set) var naturalSize: CGSize = .zero
    private(set) var currentTime: Double = 0
    private(set) var isPlaying = false
    private(set) var isPlayerReady = false

    // MARK: - Trim Range

    var trimStart: Double = 0
    var trimEnd: Double = 0

    // MARK: - Audio Control

    var isMuted: Bool = false {
        didSet { player.isMuted = isMuted }
    }
    private var initialIsMuted: Bool = false

    /// Sync player mute with export audio mode
    func syncPlayerMuteWithExportSettings() {
        player.isMuted = exportSettings.audioMode == .mute
        isMuted = exportSettings.audioMode == .mute
    }

    // MARK: - Frame Thumbnails

    private(set) var frameThumbnails: [NSImage] = []
    private(set) var isExtractingFrames = false

    // MARK: - Export Settings

    var exportSettings = ExportSettings()
    private(set) var estimatedFileSize: Int64 = 0

    // MARK: - Background Settings

    var backgroundStyle: VideoBackgroundStyle = .none
    var backgroundPadding: CGFloat = 0
    var backgroundShadowIntensity: CGFloat = 0
    var backgroundCornerRadius: CGFloat = 0

    // MARK: - Export State

    var isExporting = false
    var exportProgress: Double = 0
    var exportStatusMessage: String = "Preparing..."

    // MARK: - Unsaved Changes

    private(set) var hasUnsavedChanges = false
    private var initialTrimStart: Double = 0
    private var initialTrimEnd: Double = 0
    private var initialBackgroundStyle: VideoBackgroundStyle = .none
    private var initialBackgroundPadding: CGFloat = 0
    private var initialBackgroundShadowIntensity: CGFloat = 0
    private var initialBackgroundCornerRadius: CGFloat = 0

    // MARK: - Undo/Redo

    private(set) var canUndo = false
    private(set) var canRedo = false
    private var undoStack: [EditorAction] = []
    private var redoStack: [EditorAction] = []
    private let maxUndoStackSize = 50
    private var isUndoingOrRedoing = false

    /// Snapshot of background state before a change begins (for undo recording)
    private var bgSnapshotStyle: VideoBackgroundStyle?
    private var bgSnapshotPadding: CGFloat = 0
    private var bgSnapshotShadow: CGFloat = 0
    private var bgSnapshotCorner: CGFloat = 0

    // MARK: - Sidebar Visibility

    var isVideoInfoSidebarVisible = false
    var isRightSidebarVisible = false

    // MARK: - Computed Properties

    var trimmedDuration: Double {
        max(0, trimEnd - trimStart)
    }

    var filename: String {
        videoURL.lastPathComponent
    }

    var fileExtension: String {
        videoURL.pathExtension.lowercased()
    }

    var formattedCurrentTime: String {
        formatTime(currentTime)
    }

    var formattedDuration: String {
        formatTime(duration)
    }

    var formattedTrimmedDuration: String {
        formatTime(trimmedDuration)
    }

    var resolutionString: String {
        guard naturalSize.width > 0 && naturalSize.height > 0 else { return "—" }
        return "\(Int(naturalSize.width)) × \(Int(naturalSize.height))"
    }

    var aspectRatioString: String {
        guard naturalSize.width > 0 && naturalSize.height > 0 else { return "—" }
        let gcdValue = gcd(Int(naturalSize.width), Int(naturalSize.height))
        let w = Int(naturalSize.width) / gcdValue
        let h = Int(naturalSize.height) / gcdValue
        return "\(w):\(h)"
    }

    var fileSizeString: String {
        guard let size = cachedFileSize else { return "—" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var fileCreationDate: Date? {
        cachedFileAttributes?[.creationDate] as? Date
    }

    var fileModificationDate: Date? {
        cachedFileAttributes?[.modificationDate] as? Date
    }

    var formattedEstimatedFileSize: String {
        if estimatedFileSize > 0 {
            return "~" + ByteCountFormatter.string(fromByteCount: estimatedFileSize, countStyle: .file)
        }
        return "—"
    }

    // MARK: - Private

    private var timeObserver: Any?
    private var cachedFileAttributes: [FileAttributeKey: Any]?
    private var cachedFileSize: Int64?

    // MARK: - Init

    init(url: URL) {
        self.videoURL = url
        self.asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: self.asset)
        self.playerItem = item
        self.player = AVPlayer(playerItem: item)

        // Cache file attributes once at init
        cachedFileAttributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        cachedFileSize = cachedFileAttributes?[.size] as? Int64

        setupTimeObserver()
    }

    // MARK: - Setup

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, !self.isExporting else { return }
                self.currentTime = CMTimeGetSeconds(time)

                // Auto-pause at trim end
                if self.currentTime >= self.trimEnd && self.isPlaying {
                    self.pause()
                    self.seek(to: self.trimStart)
                }
            }
        }
    }

    // MARK: - Metadata Loading

    func loadVideo() async {
        if isGIF {
            loadGIFMetadata()
            return
        }

        do {
            let dur = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(dur)
            duration = seconds
            trimEnd = seconds
            initialTrimEnd = seconds

            if let track = try await asset.loadTracks(withMediaType: .video).first {
                let size = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let transformedSize = size.applying(transform)
                naturalSize = CGSize(
                    width: abs(transformedSize.width),
                    height: abs(transformedSize.height)
                )
            }

            recalculateEstimatedFileSize()

            // Wait for player item to become ready (shares same asset, usually instant)
            var waitAttempts = 0
            while playerItem.status == .unknown && waitAttempts < 100 {
                try await Task.sleep(for: .milliseconds(25))
                waitAttempts += 1
            }
            isPlayerReady = playerItem.status == .readyToPlay

            if !isPlayerReady {
                print("⚠️ Player not ready: \(playerItem.error?.localizedDescription ?? "unknown")")
            }
        } catch {
            print("⚠️ Failed to load video metadata: \(error)")
        }
    }

    private func loadGIFMetadata() {
        guard let meta = GIFProcessor.metadata(for: videoURL) else {
            print("⚠️ Failed to load GIF metadata: \(videoURL.lastPathComponent)")
            return
        }
        gifMetadata = meta
        gifFrameCount = meta.frameCount
        gifDuration = meta.duration
        naturalSize = meta.size

        // Initialize trim to full range
        gifTrimStartFrame = 0
        gifTrimEndFrame = meta.frameCount - 1
        initialGifTrimStartFrame = 0
        initialGifTrimEndFrame = meta.frameCount - 1

        // For compatibility with shared UI
        duration = meta.duration
        trimStart = 0
        trimEnd = meta.duration

        isPlayerReady = true
        recalculateEstimatedFileSize()
    }

    // MARK: - Frame Extraction

    func extractFrames() async {
        if isGIF {
            extractGIFFrames()
            return
        }

        guard duration > 0 else { return }

        isExtractingFrames = true
        defer { isExtractingFrames = false }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 120, height: 68)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let count = 30
        let interval = duration / Double(count)
        var images: [NSImage] = []

        for i in 0..<count {
            let time = CMTime(seconds: Double(i) * interval, preferredTimescale: 600)
            if let (cgImage, _) = try? await generator.image(at: time) {
                let image = NSImage(cgImage: cgImage, size: NSSize(width: 120, height: 68))
                images.append(image)
            }
        }
        frameThumbnails = images
    }

    private func extractGIFFrames() {
        isExtractingFrames = true
        defer { isExtractingFrames = false }

        let thumbnails = GIFProcessor.extractThumbnails(
            from: videoURL,
            count: 30,
            maxSize: CGSize(width: 120, height: 68)
        )
        frameThumbnails = thumbnails
    }

    // MARK: - Playback Control

    func play() {
        guard isPlayerReady else { return }
        if currentTime >= trimEnd || currentTime < trimStart {
            seek(to: trimStart)
        }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlayback() {
        if isPlaying { pause() } else { play() }
    }

    func toggleMute() {
        let oldValue = isMuted
        isMuted.toggle()
        recordAction(.toggleMute(old: oldValue, new: isMuted))
    }

    func seek(to time: Double) {
        let clamped = max(trimStart, min(time, trimEnd))
        currentTime = clamped
        guard isPlayerReady else { return }
        // Small tolerance for reliable rendering (zero tolerance stalls on VFR recordings)
        let tolerance = CMTime(seconds: 0.05, preferredTimescale: 600)
        player.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: tolerance,
            toleranceAfter: tolerance
        )
    }

    // MARK: - Trim Clamping

    func setTrimStart(_ time: Double, recordUndo: Bool = true) {
        let oldValue = trimStart
        let minDuration = 0.5
        let maxStart = trimEnd - minDuration
        let newValue = max(0, min(time, maxStart))
        trimStart = newValue

        if currentTime < trimStart {
            seek(to: trimStart)
        }

        if recordUndo && abs(oldValue - newValue) > 0.01 {
            recordAction(.trimStart(old: oldValue, new: newValue))
        }

        updateHasUnsavedChanges()
        recalculateEstimatedFileSize()
    }

    func setTrimEnd(_ time: Double, recordUndo: Bool = true) {
        let oldValue = trimEnd
        let minDuration = 0.5
        let minEnd = trimStart + minDuration
        let newValue = max(minEnd, min(time, duration))
        trimEnd = newValue

        if currentTime > trimEnd {
            seek(to: trimEnd)
        }

        if recordUndo && abs(oldValue - newValue) > 0.01 {
            recordAction(.trimEnd(old: oldValue, new: newValue))
        }

        updateHasUnsavedChanges()
        recalculateEstimatedFileSize()
    }

    func resetTrim() {
        trimStart = 0
        trimEnd = duration
        updateHasUnsavedChanges()
        recalculateEstimatedFileSize()
    }

    // MARK: - GIF Trim

    func setGIFTrimStart(_ frame: Int, recordUndo: Bool = true) {
        guard gifFrameCount > 1 else { return }
        let oldValue = gifTrimStartFrame
        let maxStart = gifTrimEndFrame - 1
        let newValue = max(0, min(frame, maxStart))
        gifTrimStartFrame = newValue

        if recordUndo && oldValue != newValue {
            recordAction(.gifTrimStart(old: oldValue, new: newValue))
        }
        updateHasUnsavedChanges()
        recalculateEstimatedFileSize()
    }

    func setGIFTrimEnd(_ frame: Int, recordUndo: Bool = true) {
        guard gifFrameCount > 1 else { return }
        let oldValue = gifTrimEndFrame
        let minEnd = gifTrimStartFrame + 1
        let maxEnd = gifFrameCount - 1
        let newValue = max(minEnd, min(frame, maxEnd))
        gifTrimEndFrame = newValue

        if recordUndo && oldValue != newValue {
            recordAction(.gifTrimEnd(old: oldValue, new: newValue))
        }
        updateHasUnsavedChanges()
        recalculateEstimatedFileSize()
    }

    // MARK: - Export Settings

    func updateExportSettings(_ settings: ExportSettings) {
        exportSettings = settings
        syncPlayerMuteWithExportSettings()
        recalculateEstimatedFileSize()
    }

    func recalculateEstimatedFileSize() {
        guard let sourceSize = cachedFileSize else {
            estimatedFileSize = 0
            return
        }

        if isGIF {
            // Estimate based on frame ratio * dimension ratio
            let frameRatio = gifFrameCount > 0
                ? Double(gifTrimmedFrameCount) / Double(gifFrameCount)
                : 1.0
            let exportSize = exportSettings.exportSize(from: naturalSize)
            let originalPixels = naturalSize.width * naturalSize.height
            let newPixels = exportSize.width * exportSize.height
            let pixelRatio = originalPixels > 0 ? newPixels / originalPixels : 1.0
            let estimated = Double(sourceSize) * frameRatio * pixelRatio
            estimatedFileSize = Int64(max(estimated, 1024))
            return
        }

        guard duration > 0 else {
            estimatedFileSize = 0
            return
        }

        // Calculate trim ratio
        let trimRatio = trimmedDuration / duration

        // Calculate dimension ratio
        let exportSize = exportSettings.exportSize(from: naturalSize)
        let originalPixels = naturalSize.width * naturalSize.height
        let canvasPixels = exportSize.width * exportSize.height
        let dimensionRatio = originalPixels > 0 ? canvasPixels / originalPixels : 1.0

        // Apply quality multiplier
        let qualityMultiplier = Double(exportSettings.quality.bitrateMultiplier)

        // Audio adjustment (~10% of file)
        let audioMultiplier: Double = exportSettings.audioMode == .mute ? 0.9 : 1.0

        let estimated = Double(sourceSize) * trimRatio * dimensionRatio * qualityMultiplier * audioMultiplier
        estimatedFileSize = Int64(max(estimated, 1024))
    }

    // MARK: - Sidebar Toggles

    func toggleVideoInfoSidebar() {
        isVideoInfoSidebarVisible.toggle()
    }

    func toggleRightSidebar() {
        isRightSidebarVisible.toggle()
    }

    // MARK: - Background Undo Support

    /// Call before changing any background property to save the "before" state.
    func snapshotBackgroundState() {
        guard !isUndoingOrRedoing else { return }
        bgSnapshotStyle = backgroundStyle
        bgSnapshotPadding = backgroundPadding
        bgSnapshotShadow = backgroundShadowIntensity
        bgSnapshotCorner = backgroundCornerRadius
    }

    /// Call after finishing a background change to record undo action if anything changed.
    func commitBackgroundChange() {
        guard !isUndoingOrRedoing,
              let oldStyle = bgSnapshotStyle else { return }

        // Only record if something actually changed
        let styleChanged = oldStyle != backgroundStyle
        let paddingChanged = abs(bgSnapshotPadding - backgroundPadding) > 0.01
        let shadowChanged = abs(bgSnapshotShadow - backgroundShadowIntensity) > 0.01
        let cornerChanged = abs(bgSnapshotCorner - backgroundCornerRadius) > 0.01

        guard styleChanged || paddingChanged || shadowChanged || cornerChanged else {
            bgSnapshotStyle = nil
            return
        }

        recordAction(.updateBackground(
            oldStyle: oldStyle, newStyle: backgroundStyle,
            oldPadding: bgSnapshotPadding, newPadding: backgroundPadding,
            oldShadow: bgSnapshotShadow, newShadow: backgroundShadowIntensity,
            oldCorner: bgSnapshotCorner, newCorner: backgroundCornerRadius
        ))
        bgSnapshotStyle = nil
        updateHasUnsavedChanges()
    }

    // MARK: - File Operations

    func openInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([videoURL])
    }

    // MARK: - Undo/Redo

    private func recordAction(_ action: EditorAction) {
        guard !isUndoingOrRedoing else { return }
        undoStack.append(action)
        if undoStack.count > maxUndoStackSize {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        updateUndoRedoState()
    }

    func undo() {
        guard let action = undoStack.popLast() else { return }
        isUndoingOrRedoing = true
        defer {
            isUndoingOrRedoing = false
            updateUndoRedoState()
            updateHasUnsavedChanges()
            recalculateEstimatedFileSize()
        }

        switch action {
        case .trimStart(let old, let new):
            trimStart = old
            redoStack.append(.trimStart(old: new, new: old))
        case .trimEnd(let old, let new):
            trimEnd = old
            redoStack.append(.trimEnd(old: new, new: old))
        case .toggleMute(let old, _):
            isMuted = old
            redoStack.append(.toggleMute(old: !old, new: old))
        case .updateBackground(let oldStyle, let newStyle,
                               let oldPadding, let newPadding,
                               let oldShadow, let newShadow,
                               let oldCorner, let newCorner):
            backgroundStyle = oldStyle
            backgroundPadding = oldPadding
            backgroundShadowIntensity = oldShadow
            backgroundCornerRadius = oldCorner
            redoStack.append(.updateBackground(
                oldStyle: newStyle, newStyle: oldStyle,
                oldPadding: newPadding, newPadding: oldPadding,
                oldShadow: newShadow, newShadow: oldShadow,
                oldCorner: newCorner, newCorner: oldCorner
            ))
        case .gifTrimStart(let old, let new):
            gifTrimStartFrame = old
            redoStack.append(.gifTrimStart(old: new, new: old))
        case .gifTrimEnd(let old, let new):
            gifTrimEndFrame = old
            redoStack.append(.gifTrimEnd(old: new, new: old))
        }
    }

    func redo() {
        guard let action = redoStack.popLast() else { return }
        isUndoingOrRedoing = true
        defer {
            isUndoingOrRedoing = false
            updateUndoRedoState()
            updateHasUnsavedChanges()
            recalculateEstimatedFileSize()
        }

        switch action {
        case .trimStart(let old, let new):
            trimStart = old
            undoStack.append(.trimStart(old: new, new: old))
        case .trimEnd(let old, let new):
            trimEnd = old
            undoStack.append(.trimEnd(old: new, new: old))
        case .toggleMute(let old, _):
            isMuted = old
            undoStack.append(.toggleMute(old: !old, new: old))
        case .updateBackground(let oldStyle, let newStyle,
                               let oldPadding, let newPadding,
                               let oldShadow, let newShadow,
                               let oldCorner, let newCorner):
            backgroundStyle = oldStyle
            backgroundPadding = oldPadding
            backgroundShadowIntensity = oldShadow
            backgroundCornerRadius = oldCorner
            undoStack.append(.updateBackground(
                oldStyle: newStyle, newStyle: oldStyle,
                oldPadding: newPadding, newPadding: oldPadding,
                oldShadow: newShadow, newShadow: oldShadow,
                oldCorner: newCorner, newCorner: oldCorner
            ))
        case .gifTrimStart(let old, let new):
            gifTrimStartFrame = old
            undoStack.append(.gifTrimStart(old: new, new: old))
        case .gifTrimEnd(let old, let new):
            gifTrimEndFrame = old
            undoStack.append(.gifTrimEnd(old: new, new: old))
        }
    }

    private func updateUndoRedoState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    // MARK: - Unsaved Changes

    private func updateHasUnsavedChanges() {
        if isGIF {
            let trimStartChanged = gifTrimStartFrame != initialGifTrimStartFrame
            let trimEndChanged = gifTrimEndFrame != initialGifTrimEndFrame
            let dimensionChanged = exportSettings.dimensionPreset != initialGifDimensionPreset
            hasUnsavedChanges = trimStartChanged || trimEndChanged || dimensionChanged
            return
        }

        let startChanged = abs(trimStart - initialTrimStart) > 0.01
        let endChanged = abs(trimEnd - initialTrimEnd) > 0.01
        let muteChanged = isMuted != initialIsMuted
        let bgStyleChanged = backgroundStyle != initialBackgroundStyle
        let bgPaddingChanged = abs(backgroundPadding - initialBackgroundPadding) > 0.01
        let bgShadowChanged = abs(backgroundShadowIntensity - initialBackgroundShadowIntensity) > 0.01
        let bgCornerChanged = abs(backgroundCornerRadius - initialBackgroundCornerRadius) > 0.01

        hasUnsavedChanges = startChanged || endChanged || muteChanged
            || bgStyleChanged || bgPaddingChanged || bgShadowChanged || bgCornerChanged
    }

    func markAsSaved() {
        hasUnsavedChanges = false

        if isGIF {
            initialGifTrimStartFrame = gifTrimStartFrame
            initialGifTrimEndFrame = gifTrimEndFrame
            initialGifDimensionPreset = exportSettings.dimensionPreset
        } else {
            initialTrimStart = trimStart
            initialTrimEnd = trimEnd
            initialIsMuted = isMuted
            initialBackgroundStyle = backgroundStyle
            initialBackgroundPadding = backgroundPadding
            initialBackgroundShadowIntensity = backgroundShadowIntensity
            initialBackgroundCornerRadius = backgroundCornerRadius
        }

        undoStack.removeAll()
        redoStack.removeAll()
        updateUndoRedoState()
    }

    // MARK: - Formatting

    func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }

    // MARK: - Helpers

    private func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }

    // MARK: - Cleanup

    func cleanup() {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    deinit {
        // Safety net: remove time observer if cleanup() was not called
        // (e.g., window force-closed without SwiftUI onDisappear firing)
        MainActor.assumeIsolated {
            if let observer = timeObserver {
                player.removeTimeObserver(observer)
            }
        }
    }
}
