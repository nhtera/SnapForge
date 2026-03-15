import SwiftUI
import AppKit
import AVFoundation

/// Dedicated coordinator for all recording-related window management and lifecycle.
/// Extracted from `AppCoordinator` to keep each coordinator focused and manageable.
@MainActor
@Observable
final class RecordingCoordinator {
    static let shared = RecordingCoordinator()

    // MARK: - Window References

    private var recordingBorderWindow: NSWindow?
    private var recordingToolbarPanel: NSPanel?
    private var recordingCountdownWindow: NSWindow?

    /// Pending recording rect (after area selection, before user clicks Record)
    private var pendingRecordingRect: CGRect?
    private var isGIFMode = false

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
        let recorder = ScreenRecordingService.shared
        if let savedURL = await recorder.stopRecording() {
            print("✅ Recording saved: \(savedURL.path)")

            if isGIFMode {
                await convertToGIF(videoURL: savedURL)
            }
        }
        AppEnvironment.shared.isRecording = false
        isGIFMode = false

        // Stop click visualizer if it was running
        ClickVisualizer.shared.stop()
        KeystrokeVisualizer.shared.stop()

        dismissRecordingIndicator()
    }

    func cancelRecording() async {
        let recorder = ScreenRecordingService.shared
        await recorder.cancelRecording()
        AppEnvironment.shared.isRecording = false
        isGIFMode = false
        dismissRecordingIndicator()
    }

    func toggleRecording() {
        if AppEnvironment.shared.isRecording {
            Task { @MainActor in
                await stopRecording()
            }
        } else {
            startRecording()
        }
    }

    func showRecordingIndicator(in rect: NSRect) {
        let cocoaRect = cgToCocoaRect(rect)

        // 1. Border overlay — click-through
        showBorderWindow(cocoaRect: cocoaRect, isPreRecord: false)

        // 2. Toolbar panel — only if showRecordingControls is enabled
        if UserDefaults.standard.bool(forKey: SettingsKey.showRecordingControls) {
            let toolbarView = RecordingToolbarView(isGIFMode: isGIFMode)
            showToolbarPanel(toolbarView: toolbarView, cocoaRect: cocoaRect)
        }
    }

    func dismissRecordingIndicator() {
        recordingBorderWindow?.close()
        recordingBorderWindow = nil
        recordingToolbarPanel?.close()
        recordingToolbarPanel = nil
    }

    /// Clean up all recording windows.
    func cleanup() {
        recordingBorderWindow?.close()
        recordingToolbarPanel?.close()
        recordingCountdownWindow?.close()
    }

    // MARK: - Pre-Record UI

    /// Show pre-record toolbar with highlighted area border (two separate windows)
    private func showPreRecordIndicator(for rect: CGRect) {
        pendingRecordingRect = rect
        let cocoaRect = cgToCocoaRect(rect)

        // 1. Border overlay — click-through
        showBorderWindow(cocoaRect: cocoaRect, isPreRecord: true)

        // 2. Toolbar panel — non-activating, accepts first mouse
        let toolbarView = PreRecordToolbarView(
            onStartVideo: { [weak self] in
                guard let self, let rect = self.pendingRecordingRect else { return }
                self.isGIFMode = false
                Task { @MainActor in
                    await self.beginRecording(in: rect)
                }
            },
            onStartGIF: { [weak self] in
                guard let self, let rect = self.pendingRecordingRect else { return }
                self.isGIFMode = true
                Task { @MainActor in
                    await self.beginRecording(in: rect)
                }
            },
            onCancel: { [weak self] in
                self?.dismissRecordingIndicator()
                self?.pendingRecordingRect = nil
            }
        )
        showToolbarPanel(toolbarView: toolbarView, cocoaRect: cocoaRect)
    }

    // MARK: - Recording Lifecycle

    private func beginRecording(in rect: CGRect) async {
        let defaults = UserDefaults.standard

        // Show countdown before recording if enabled
        if defaults.bool(forKey: SettingsKey.showRecordingCountdown) {
            dismissRecordingIndicator()
            await withCheckedContinuation { continuation in
                showRecordingCountdown(seconds: 3) {
                    continuation.resume()
                }
            }
        }

        let recorder = ScreenRecordingService.shared
        let storage = AppEnvironment.shared.storageService

        // Resolve codec from settings
        let codecString = defaults.string(forKey: SettingsKey.recordingCodec) ?? "h264"
        let codec: AVVideoCodecType = (codecString == "hevc") ? .hevc : .h264

        // Resolve resolution scale
        let resolutionSetting = defaults.string(forKey: SettingsKey.recordingResolution) ?? "retina"
        let useRetinaScale = (resolutionSetting == "retina")

        do {
            try await recorder.prepareRecording(
                rect: rect,
                format: .mov,
                quality: .high,
                fps: defaults.integer(forKey: SettingsKey.recordingFPS),
                captureSystemAudio: true,
                captureMicrophone: false,
                showCursor: defaults.bool(forKey: SettingsKey.showCursorInRecording),
                codec: codec,
                useRetinaScale: useRetinaScale,
                saveDirectory: storage.snapForgeDirectory
            )
            try await recorder.startRecording()

            AppEnvironment.shared.isRecording = true
            pendingRecordingRect = nil

            // Start click visualizer if highlight-clicks is enabled
            if defaults.bool(forKey: SettingsKey.highlightClicks) {
                ClickVisualizer.shared.start()
            }

            // Start keystroke visualizer if show-keystrokes is enabled
            if defaults.bool(forKey: SettingsKey.showKeystrokes) {
                KeystrokeVisualizer.shared.start()
            }

            // Switch from pre-record to recording mode
            showRecordingIndicator(in: rect)
        } catch {
            print("❌ Recording failed: \(error)")
        }
    }

    private func convertToGIF(videoURL: URL) async {
        let encoder = GIFEncoder()
        let gifURL = videoURL.deletingPathExtension().appendingPathExtension("gif")
        let defaults = UserDefaults.standard
        let config = GIFEncoder.Configuration(
            fps: defaults.integer(forKey: SettingsKey.gifFPS),
            maxWidth: defaults.integer(forKey: SettingsKey.gifMaxWidth),
            loopCount: defaults.integer(forKey: SettingsKey.gifLoopCount),
            quality: Float(defaults.double(forKey: SettingsKey.gifQuality))
        )
        do {
            try await encoder.encode(
                inputURL: videoURL,
                outputURL: gifURL,
                config: config
            ) { @Sendable framesProcessed, totalFrames in
                print("GIF encoding: \(framesProcessed)/\(totalFrames)")
            }
            print("✅ GIF saved: \(gifURL.lastPathComponent)")
            try? FileManager.default.removeItem(at: videoURL)
        } catch {
            print("❌ GIF encoding failed: \(error)")
        }
    }

    // MARK: - Countdown

    private func showRecordingCountdown(seconds: Int, onComplete: @escaping () -> Void) {
        guard let screen = NSScreen.main else {
            onComplete()
            return
        }

        let countdownView = CountdownOverlayView(
            totalSeconds: seconds,
            captureRect: .zero,
            screenSize: screen.frame.size,
            onComplete: { [weak self] in
                self?.recordingCountdownWindow?.close()
                self?.recordingCountdownWindow = nil
                onComplete()
            },
            onCancel: { [weak self] in
                self?.recordingCountdownWindow?.close()
                self?.recordingCountdownWindow = nil
                onComplete()  // Must resume continuation so caller doesn't hang
            }
        )

        let hostingView = NSHostingView(rootView: countdownView)
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.makeKeyAndOrderFront(nil)
        recordingCountdownWindow = window
    }

    // MARK: - Window Helpers

    /// Click-through border window — shows area highlight only.
    private func showBorderWindow(cocoaRect: CGRect, isPreRecord: Bool) {
        recordingBorderWindow?.close()

        let borderView = RecordingBorderView(isPreRecord: isPreRecord)
        let hostingView = NSHostingView(rootView: borderView)

        let window = NSWindow(
            contentRect: cocoaRect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true    // Click-through!
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.orderFrontRegardless()

        recordingBorderWindow = window
    }

    /// Non-activating toolbar panel — buttons respond on first click.
    private func showToolbarPanel<V: View>(toolbarView: V, cocoaRect: CGRect) {
        recordingToolbarPanel?.close()

        let hostingView = FirstMouseHostingView(rootView: toolbarView)
        let intrinsicSize = hostingView.fittingSize

        // Position toolbar centered below the border
        let toolbarRect = CGRect(
            x: cocoaRect.midX - intrinsicSize.width / 2,
            y: cocoaRect.origin.y - intrinsicSize.height - 8,
            width: intrinsicSize.width,
            height: intrinsicSize.height
        )

        let panel = NSPanel(
            contentRect: toolbarRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.level = .statusBar + 1
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.orderFrontRegardless()

        recordingToolbarPanel = panel
    }

    // MARK: - Coordinate Helpers

    /// Convert CG screen coordinates (y=0 at top) to Cocoa screen coordinates (y=0 at bottom)
    private func cgToCocoaRect(_ cgRect: CGRect) -> CGRect {
        guard let screenHeight = NSScreen.main?.frame.height else { return cgRect }
        return CGRect(
            x: cgRect.origin.x,
            y: screenHeight - cgRect.origin.y - cgRect.height,
            width: cgRect.width,
            height: cgRect.height
        )
    }
}
