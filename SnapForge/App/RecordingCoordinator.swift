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

    // MARK: - Event Monitors

    private var localEscapeMonitor: Any?
    private var globalEscapeMonitor: Any?
    private var stopHotkeyMonitor: Any?

    // MARK: - Dim Overlay

    private var dimOverlayWindow: NSWindow?

    // MARK: - Extracted Managers

    private let countdownManager = RecordingCountdownManager()
    private let gifConverter = RecordingGIFConverter()

    // MARK: - Phase 2 Annotation
    private let annotationManager = RecordingAnnotationManager()
    var annotationState: RecordingAnnotationState? { annotationManager.annotationState }

    // MARK: - Webcam Overlay
    private var webcamManager: WebcamOverlayManager?

    // MARK: - Phase 3 Region Overlay
    private var regionOverlayWindow: RecordingRegionOverlayWindow?
    private var regionState: RecordingRegionState?

    // MARK: - Screen Lock Auto-Pause
    private var screenSleepObserver: NSObjectProtocol?
    private var screenWakeObserver: NSObjectProtocol?
    private var wasPausedBySleep = false

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
        removeScreenLockObservers()

        let recorder = ScreenRecordingService.shared
        let savedURL = await recorder.stopRecording()
        let isGIF = toolbarState?.outputMode == .gif

        AppEnvironment.shared.isRecording = false
        ClickVisualizer.shared.stop()
        KeystrokeVisualizer.shared.stop()
        webcamManager?.hide()
        webcamManager = nil
        dismissRecordingIndicator()

        guard let savedURL else {
            recorder.releaseDirectoryAccess()
            return
        }
        AppLogger.recording.info("Recording saved: \(savedURL.path)")

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
        removeScreenLockObservers()
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
        removeEscapeMonitors()
        removeStopHotkey()
        recordingBorderWindow?.close()
        recordingBorderWindow = nil
        recordingToolbarPanel?.close()
        recordingToolbarPanel = nil
        regionOverlayWindow?.close()
        regionOverlayWindow = nil
        dimOverlayWindow?.close()
        dimOverlayWindow = nil
        countdownManager.dismissCountdown()
        annotationManager.dismiss()
    }

    // MARK: - Escape Key & Hotkey Monitors

    private func setupEscapeMonitors() {
        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                Task { @MainActor in
                    self?.dismissRecordingIndicator()
                    self?.pendingRecordingRect = nil
                }
                return nil // consume event
            }
            return event
        }
        globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in
                    self?.dismissRecordingIndicator()
                    self?.pendingRecordingRect = nil
                }
            }
        }
    }

    private func removeEscapeMonitors() {
        if let monitor = localEscapeMonitor { NSEvent.removeMonitor(monitor); localEscapeMonitor = nil }
        if let monitor = globalEscapeMonitor { NSEvent.removeMonitor(monitor); globalEscapeMonitor = nil }
    }

    private func setupStopHotkey() {
        stopHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Cmd+Shift+R to stop recording
            if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 15 {
                Task { @MainActor in await self?.stopRecording() }
            }
        }
    }

    private func removeStopHotkey() {
        if let monitor = stopHotkeyMonitor { NSEvent.removeMonitor(monitor); stopHotkeyMonitor = nil }
    }

    // MARK: - Last Recording Area

    /// Load last recording area from UserDefaults (supports both dictionary and legacy array format)
    func loadLastRecordingArea() -> CGRect? {
        let defaults = UserDefaults.standard
        // Dictionary format (new)
        if let dict = defaults.dictionary(forKey: SettingsKey.lastRecordingArea),
           let x = dict["x"] as? Double, let y = dict["y"] as? Double,
           let w = dict["width"] as? Double, let h = dict["height"] as? Double {
            let rect = CGRect(x: x, y: y, width: w, height: h)
            return isRectVisibleOnScreen(rect) ? rect : nil
        }
        // Legacy array format
        if let arr = defaults.array(forKey: SettingsKey.lastRecordingArea) as? [Double], arr.count == 4 {
            let rect = CGRect(x: arr[0], y: arr[1], width: arr[2], height: arr[3])
            return isRectVisibleOnScreen(rect) ? rect : nil
        }
        return nil
    }

    /// Check if rect is visible on any connected screen
    private func isRectVisibleOnScreen(_ rect: CGRect) -> Bool {
        NSScreen.screens.contains { $0.frame.intersects(rect) }
    }

    /// Restore last recording area — dismiss current UI, show pre-record for saved area
    func restoreLastRecordingArea() {
        guard let rect = loadLastRecordingArea() else { return }
        dismissRecordingIndicator()
        showPreRecordIndicator(for: rect)
    }

    // MARK: - Pre-Record UI

    func showPreRecordIndicator(for rect: CGRect) {
        pendingRecordingRect = rect
        let cocoaRect = cgToCocoaRect(rect)
        let isFullscreen = (rect == NSScreen.main?.frame)

        if !isFullscreen, let screen = NSScreen.main {
            // Interactive region overlay — drag to move, handles to resize
            let rState = RecordingRegionState(rect: cocoaRect)
            rState.onRectChanged = { [weak self] newCocoaRect in
                self?.handleRegionRectChanged(newCocoaRect)
            }
            rState.onCancel = { [weak self] in
                self?.dismissRecordingIndicator()
                self?.pendingRecordingRect = nil
            }
            regionState = rState

            let overlay = RecordingRegionOverlayWindow(screen: screen, state: rState)
            overlay.makeKeyAndOrderFront(nil)
            regionOverlayWindow = overlay
        } else {
            // Fullscreen: simple non-interactive border
            showBorderWindow(cocoaRect: cocoaRect, isPreRecord: true)
        }

        let state = RecordingToolbarState()
        state.captureMode = isFullscreen ? .fullscreen : .area
        state.onCaptureModeChanged = { [weak self] mode in
            self?.handleCaptureModeChange(mode)
        }
        // Wire aspect ratio → region state + immediately reshape
        state.onAspectRatioChanged = { [weak self] ratio in
            guard let self, let rState = self.regionState else { return }
            rState.lockedAspectRatio = ratio.value
            // Immediately reshape region to match the selected ratio
            if let ratioValue = ratio.value {
                var r = rState.rect
                let center = CGPoint(x: r.midX, y: r.midY)
                let newHeight = r.width / ratioValue
                r.size.height = newHeight
                r.origin.y = center.y - newHeight / 2
                // Clamp to screen
                if let screen = NSScreen.main {
                    let sf = screen.frame
                    r.origin.x = max(sf.minX, min(r.origin.x, sf.maxX - r.width))
                    r.origin.y = max(sf.minY, min(r.origin.y, sf.maxY - r.height))
                }
                rState.rect = r
                rState.onRectChanged?(r)
                self.regionOverlayWindow?.contentView?.needsDisplay = true
            }
        }
        // Wire size preset → resize region centered
        state.onSizePresetSelected = { [weak self] size in
            guard let self, let rState = self.regionState else { return }
            let center = CGPoint(x: rState.rect.midX, y: rState.rect.midY)
            var newRect = CGRect(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2,
                width: size.width,
                height: size.height
            )
            // Clamp to screen bounds
            if let screen = NSScreen.main {
                let sf = screen.frame
                if newRect.width > sf.width { newRect.size.width = sf.width }
                if newRect.height > sf.height { newRect.size.height = sf.height }
                newRect.origin.x = max(sf.minX, min(newRect.origin.x, sf.maxX - newRect.width))
                newRect.origin.y = max(sf.minY, min(newRect.origin.y, sf.maxY - newRect.height))
            }
            rState.rect = newRect
            rState.onRectChanged?(newRect)
            self.regionOverlayWindow?.contentView?.needsDisplay = true
        }
        toolbarState = state

        // Determine if restore-area button should be shown
        let hasValidLastArea = loadLastRecordingArea() != nil

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
            },
            onRestoreArea: hasValidLastArea ? { [weak self] in self?.restoreLastRecordingArea() } : nil
        )

        let panel = RecordingToolbarWindow()
        panel.setContent(toolbarView)
        panel.positionBelowRect(cocoaRect)
        panel.orderFrontRegardless()
        recordingToolbarPanel = panel

        setupEscapeMonitors()
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

        // Setup annotation manager with pre-computed Cocoa rect
        annotationManager.setup(anchorPanel: nil, cocoaRect: cocoaRect)

        let toolbarView = RecordingStatusBarView(
            isGIFMode: toolbarState?.outputMode == .gif,
            annotationState: annotationManager.annotationState,
            recordingSize: CGSize(width: rect.width, height: rect.height),
            onRestart: { [weak self] in self?.restartRecording() },
            onDelete: { Task { await AppCoordinator.shared.cancelRecording() } },
            onStop: { Task { await AppCoordinator.shared.stopRecording() } }
        )

        let panel = RecordingToolbarWindow()
        panel.setContent(toolbarView, draggable: true)
        panel.positionBelowRect(cocoaRect)
        panel.orderFrontRegardless()
        recordingToolbarPanel = panel

        // Update annotation toolbar anchor to the actual panel
        annotationManager.updateAnchorPanel(panel)

        setupStopHotkey()
        showDimOverlayIfEnabled(recordingRect: rect)
    }

    func dismissRecordingIndicator() {
        removeEscapeMonitors()
        removeStopHotkey()
        recordingBorderWindow?.close()
        recordingBorderWindow = nil
        recordingToolbarPanel?.close()
        recordingToolbarPanel = nil
        regionOverlayWindow?.close()
        regionOverlayWindow = nil
        regionState = nil
        dimOverlayWindow?.close()
        dimOverlayWindow = nil
    }

    // MARK: - Recording Lifecycle

    private func beginRecording(in rect: CGRect) async {
        let defaults = UserDefaults.standard
        let countdownSeconds = defaults.integer(forKey: SettingsKey.recordingCountdownSeconds)

        // Always dismiss pre-record UI before starting recording
        dismissRecordingIndicator()

        if countdownSeconds > 0 {
            await countdownManager.showCountdown(seconds: countdownSeconds, captureRect: rect)
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
                let cocoaRect = cgToCocoaRect(rect)
                ClickVisualizer.shared.start(recordingRect: cocoaRect)
                // Add click overlay to SCStream so effects appear in recording
                if let windowID = ClickVisualizer.shared.overlayWindowID {
                    await recorder.addExceptedWindows([windowID])
                }
            }
            if toolbarState?.showKeystrokes ?? defaults.bool(forKey: SettingsKey.showKeystrokes) {
                KeystrokeVisualizer.shared.start()
            }

            // Start webcam overlay if enabled
            if toolbarState?.webcamEnabled ?? defaults.bool(forKey: SettingsKey.webcamEnabled) {
                let manager = WebcamOverlayManager()
                manager.show()
                webcamManager = manager
                // Add webcam overlay to SCStream so it appears in recording
                if let windowID = manager.overlayWindowID {
                    await recorder.addExceptedWindows([windowID])
                }
            }

            // Save last recording area (dictionary format for readability)
            let areaDict: [String: Double] = [
                "x": rect.origin.x, "y": rect.origin.y,
                "width": rect.width, "height": rect.height
            ]
            defaults.set(areaDict, forKey: SettingsKey.lastRecordingArea)

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
            registerScreenLockObservers()
        } catch {
            AppLogger.recording.error("Recording failed: \(error.localizedDescription)")
            AppEnvironment.shared.showUserError("Recording failed: \(error.localizedDescription)")
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

    // MARK: - Screen Lock Auto-Pause

    private func registerScreenLockObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        screenSleepObserver = nc.addObserver(
            forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                let recorder = ScreenRecordingService.shared
                if recorder.state == .recording, !recorder.isPaused {
                    recorder.pauseRecording()
                    self?.wasPausedBySleep = true
                }
            }
        }
        screenWakeObserver = nc.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                if self?.wasPausedBySleep == true {
                    ScreenRecordingService.shared.resumeRecording()
                    self?.wasPausedBySleep = false
                }
            }
        }
    }

    private func removeScreenLockObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        if let obs = screenSleepObserver { nc.removeObserver(obs) }
        if let obs = screenWakeObserver { nc.removeObserver(obs) }
        screenSleepObserver = nil
        screenWakeObserver = nil
        wasPausedBySleep = false
    }

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

    // MARK: - Dim Overlay

    /// Show click-through dim overlay outside recording region if enabled in settings
    private func showDimOverlayIfEnabled(recordingRect: CGRect) {
        guard UserDefaults.standard.bool(forKey: SettingsKey.dimScreenWhileRecording),
              let screen = NSScreen.main else { return }
        let cocoaRect = cgToCocoaRect(recordingRect)

        let window = NSWindow(
            contentRect: screen.frame, styleMask: .borderless,
            backing: .buffered, defer: false
        )
        let dimView = RecordingDimOverlayNSView(cutoutRect: cocoaRect)
        window.contentView = dimView
        // Below border (.floating) and canvas (.floating + 1); toolbars at .popUpMenu
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.orderFrontRegardless()
        dimOverlayWindow = window
    }

    // MARK: - Window Helpers

    private func showBorderWindow(cocoaRect: CGRect, isPreRecord: Bool) {
        recordingBorderWindow?.close()
        let borderConfig = isPreRecord ? nil : RecordingBorderConfiguration()
        // Skip border window entirely if style is .none during active recording
        if !isPreRecord, let config = borderConfig, config.style == .none { return }
        let borderView = RecordingBorderView(isPreRecord: isPreRecord, borderConfig: borderConfig)
        let hostingView = NSHostingView(rootView: borderView)
        let window = NSWindow(
            contentRect: cocoaRect, styleMask: .borderless,
            backing: .buffered, defer: false
        )
        window.contentView = hostingView
        // Always .floating — canvas at .floating+1 renders above, toolbars at .popUpMenu
        window.level = .floating
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
