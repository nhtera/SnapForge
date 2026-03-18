import SwiftUI
import AppKit
import AVFoundation

/// Orchestrates recording-related window management and lifecycle.
@MainActor
@Observable
final class RecordingCoordinator {
    static let shared = RecordingCoordinator()

    // MARK: - Window References

    private var recordingBorderWindow: NSWindow?
    private var recordingToolbarPanel: RecordingToolbarWindow?

    // MARK: - State

    private var pendingRecordingRect: CGRect?
    private var toolbarState: RecordingToolbarState?
    private var timerLimitTask: Task<Void, Never>?

    // MARK: - Extracted Managers

    private let countdownManager = RecordingCountdownManager()
    private let gifConverter = RecordingGIFConverter()

    // MARK: - Phase 2 Annotation
    private let annotationManager = RecordingAnnotationManager()
    var annotationState: RecordingAnnotationState? { annotationManager.annotationState }

    // MARK: - Phase 3 Region Overlay
    private var regionOverlayWindow: RecordingRegionOverlayWindow?
    private var regionState: RecordingRegionState?

    private init() {}

    // MARK: - Public API

    func startRecording() {
        let manager = CaptureSessionManager.shared
        manager.startRecordingAreaSelection { [weak self] rect in
            guard let self else { return }
            Task { @MainActor in
                self.showPreRecordIndicator(for: rect)
            }
        }
    }

    func startFullscreenRecording() {
        guard let screen = NSScreen.main else { return }
        showPreRecordIndicator(for: screen.frame)
    }

    func stopRecording() async {
        timerLimitTask?.cancel()
        timerLimitTask = nil
        annotationManager.dismiss()

        let recorder = ScreenRecordingService.shared
        let savedURL = await recorder.stopRecording()
        let isGIF = toolbarState?.outputMode == .gif

        AppEnvironment.shared.isRecording = false
        ClickVisualizer.shared.stop()
        KeystrokeVisualizer.shared.stop()
        dismissRecordingIndicator()

        guard let savedURL else {
            recorder.releaseDirectoryAccess()
            return
        }
        print("✅ Recording saved: \(savedURL.path)")

        if isGIF {
            // Convert GIF in background, show Quick Access when ready
            let gifURL = await gifConverter.convert(videoURL: savedURL)
            handlePostRecordingActions(fileURL: gifURL ?? savedURL)
        } else {
            handlePostRecordingActions(fileURL: savedURL)
        }

        // Release sandbox scoped access after all file operations complete
        recorder.releaseDirectoryAccess()
    }

    func cancelRecording() async {
        timerLimitTask?.cancel()
        timerLimitTask = nil
        annotationManager.dismiss()
        await ScreenRecordingService.shared.cancelRecording()
        AppEnvironment.shared.isRecording = false
        dismissRecordingIndicator()
    }

    func toggleRecording() {
        if AppEnvironment.shared.isRecording {
            Task { @MainActor in await stopRecording() }
        } else {
            startRecording()
        }
    }

    func cleanup() {
        recordingBorderWindow?.close()
        recordingBorderWindow = nil
        recordingToolbarPanel?.close()
        recordingToolbarPanel = nil
        regionOverlayWindow?.close()
        regionOverlayWindow = nil
        countdownManager.dismissCountdown()
        annotationManager.dismiss()
    }

    // MARK: - Pre-Record UI

    func showPreRecordIndicator(for rect: CGRect) {
        pendingRecordingRect = rect
        let cocoaRect = cgToCocoaRect(rect)
        let isFullscreen = (rect == NSScreen.main?.frame)

        // Simple border rectangle around selected area (no dim overlay)
        showBorderWindow(cocoaRect: cocoaRect, isPreRecord: true)

        let state = RecordingToolbarState()
        state.captureMode = isFullscreen ? .fullscreen : .area
        state.onCaptureModeChanged = { [weak self] mode in
            self?.handleCaptureModeChange(mode)
        }
        toolbarState = state

        let toolbarView = PreRecordToolbarView(
            state: state,
            onRecord: { [weak self] in
                guard let self, let rect = self.pendingRecordingRect else { return }
                Task { @MainActor in await self.beginRecording(in: rect) }
            },
            onCapture: { [weak self] in self?.captureScreenshotFromSetup() },
            onCancel: { [weak self] in
                self?.dismissRecordingIndicator()
                self?.pendingRecordingRect = nil
            }
        )

        let panel = RecordingToolbarWindow()
        panel.setContent(toolbarView)
        panel.positionBelowRect(cocoaRect)
        panel.orderFrontRegardless()
        recordingToolbarPanel = panel
    }

    /// Handle region rect changes from the interactive overlay (converts Cocoa back to CG)
    private func handleRegionRectChanged(_ cocoaRect: CGRect) {
        guard let screenHeight = NSScreen.main?.frame.height else { return }
        let cgRect = CGRect(
            x: cocoaRect.origin.x,
            y: screenHeight - cocoaRect.origin.y - cocoaRect.height,
            width: cocoaRect.width,
            height: cocoaRect.height
        )
        pendingRecordingRect = cgRect
        recordingToolbarPanel?.positionBelowRect(cocoaRect)
    }

    func showRecordingIndicator(in rect: NSRect) {
        let cocoaRect = cgToCocoaRect(rect)
        showBorderWindow(cocoaRect: cocoaRect, isPreRecord: false)

        guard UserDefaults.standard.bool(forKey: SettingsKey.showRecordingControls) else { return }

        // Setup annotation manager
        annotationManager.setup(
            anchorPanel: nil, recordingRect: rect,
            cocoaRectProvider: { [weak self] r in self?.cgToCocoaRect(r) ?? r }
        )

        let toolbarView = RecordingStatusBarView(
            isGIFMode: toolbarState?.outputMode == .gif,
            annotationState: annotationManager.annotationState,
            onRestart: { [weak self] in self?.restartRecording() },
            onDelete: { Task { await AppCoordinator.shared.cancelRecording() } },
            onStop: { Task { await AppCoordinator.shared.stopRecording() } }
        )

        let panel = RecordingToolbarWindow()
        panel.setContent(toolbarView, draggable: true)
        panel.positionBelowRect(cocoaRect)
        panel.orderFrontRegardless()
        recordingToolbarPanel = panel

        // Update annotation manager with the actual panel reference
        annotationManager.setup(
            anchorPanel: panel, recordingRect: rect,
            cocoaRectProvider: { [weak self] r in self?.cgToCocoaRect(r) ?? r }
        )
    }

    func dismissRecordingIndicator() {
        recordingBorderWindow?.close()
        recordingBorderWindow = nil
        recordingToolbarPanel?.close()
        recordingToolbarPanel = nil
        regionOverlayWindow?.close()
        regionOverlayWindow = nil
        regionState = nil
    }

    // MARK: - Recording Lifecycle

    private func beginRecording(in rect: CGRect) async {
        let defaults = UserDefaults.standard
        let countdownSeconds = defaults.integer(forKey: SettingsKey.recordingCountdownSeconds)

        // Always dismiss pre-record UI before starting recording
        dismissRecordingIndicator()

        if countdownSeconds > 0 {
            await countdownManager.showCountdown(seconds: countdownSeconds)
        }

        let recorder = ScreenRecordingService.shared
        let storage = AppEnvironment.shared.storageService
        let codecString = defaults.string(forKey: SettingsKey.recordingCodec) ?? "h264"
        let codec: AVVideoCodecType = (codecString == "hevc") ? .hevc : .h264
        let resolutionSetting = defaults.string(forKey: SettingsKey.recordingResolution) ?? "retina"

        let format = toolbarState?.videoFormat ?? .mov
        let quality = toolbarState?.videoQuality ?? .high
        let systemAudio = toolbarState?.isSystemAudioEnabled ?? true
        let mic = toolbarState?.isMicEnabled ?? false

        do {
            try await recorder.prepareRecording(
                rect: rect, format: format, quality: quality,
                fps: defaults.integer(forKey: SettingsKey.recordingFPS),
                captureSystemAudio: systemAudio, captureMicrophone: mic,
                showCursor: defaults.bool(forKey: SettingsKey.showCursorInRecording),
                codec: codec, useRetinaScale: resolutionSetting == "retina",
                saveDirectory: storage.snapForgeDirectory
            )
            try await recorder.startRecording()
            AppEnvironment.shared.isRecording = true
            pendingRecordingRect = rect

            if toolbarState?.highlightClicks ?? defaults.bool(forKey: SettingsKey.highlightClicks) {
                ClickVisualizer.shared.start()
            }
            if toolbarState?.showKeystrokes ?? defaults.bool(forKey: SettingsKey.showKeystrokes) {
                KeystrokeVisualizer.shared.start()
            }

            // Save last recording area
            let areaData = [rect.origin.x, rect.origin.y, rect.width, rect.height]
            defaults.set(areaData, forKey: SettingsKey.lastRecordingArea)

            // Start timer limit if configured
            let limit = defaults.integer(forKey: SettingsKey.recordingTimerLimit)
            if limit > 0 {
                timerLimitTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(limit))
                    guard !Task.isCancelled else { return }
                    await self.stopRecording()
                }
            }

            showRecordingIndicator(in: rect)
        } catch {
            print("❌ Recording failed: \(error)")
        }
    }

    private func restartRecording() {
        guard let rect = pendingRecordingRect else { return }
        Task { @MainActor in
            await cancelRecording()
            try? await Task.sleep(for: .milliseconds(100))
            await beginRecording(in: rect)
        }
    }

    // MARK: - Capture Mode

    private func handleCaptureModeChange(_ mode: RecordingMode) {
        switch mode {
        case .fullscreen:
            guard let screen = NSScreen.main else { return }
            pendingRecordingRect = screen.frame
            dismissRecordingIndicator()
            showPreRecordIndicator(for: screen.frame)
        case .area, .window:
            dismissRecordingIndicator()
            pendingRecordingRect = nil
            let manager = CaptureSessionManager.shared
            manager.startRecordingAreaSelection { [weak self] rect in
                guard let self else { return }
                Task { @MainActor in self.showPreRecordIndicator(for: rect) }
            }
        }
    }

    private func captureScreenshotFromSetup() {
        guard pendingRecordingRect != nil else { return }
        dismissRecordingIndicator()
        pendingRecordingRect = nil
        // Trigger area capture mode for screenshot
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            CaptureSessionManager.shared.startCapture(mode: .area)
        }
    }

    // MARK: - Post-Recording Actions

    private func handlePostRecordingActions(fileURL: URL) {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: SettingsKey.autoCopyRecording) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([fileURL as NSURL])
        }
        if defaults.bool(forKey: SettingsKey.autoOpenRecording) {
            NSWorkspace.shared.open(fileURL)
        } else if defaults.bool(forKey: SettingsKey.showQuickAccess) {
            AppCoordinator.shared.showVideoQuickAccess(videoURL: fileURL, at: NSEvent.mouseLocation)
        }
    }

    // MARK: - Annotation UI (Phase 2) — delegated to RecordingAnnotationManager

    // MARK: - Window Helpers

    private func showBorderWindow(cocoaRect: CGRect, isPreRecord: Bool) {
        recordingBorderWindow?.close()
        let borderView = RecordingBorderView(isPreRecord: isPreRecord)
        let hostingView = NSHostingView(rootView: borderView)
        let window = NSWindow(
            contentRect: cocoaRect, styleMask: .borderless,
            backing: .buffered, defer: false
        )
        window.contentView = hostingView
        // Pre-record: use .floating so popovers can appear above it
        // Recording: use .statusBar so it stays above everything
        window.level = isPreRecord ? .floating : .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.orderFrontRegardless()
        recordingBorderWindow = window
    }

    /// Convert CG screen coordinates (y=0 at top) to Cocoa (y=0 at bottom)
    func cgToCocoaRect(_ cgRect: CGRect) -> CGRect {
        guard let screenHeight = NSScreen.main?.frame.height else { return cgRect }
        return CGRect(
            x: cgRect.origin.x,
            y: screenHeight - cgRect.origin.y - cgRect.height,
            width: cgRect.width,
            height: cgRect.height
        )
    }
}
