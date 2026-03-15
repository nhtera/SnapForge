import SwiftUI
import AppKit
import AVFoundation

/// NSPanel subclass that stays interactive even when the app is inactive.
/// Ensures Quick Access overlay buttons remain clickable after a second capture.
private class QuickAccessPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// NSView that accepts clicks without requiring the window to be activated first.
private class FirstMouseView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Central coordinator for window management, z-ordering, and navigation.
/// Follows Snapzy's Coordinator Pattern — single source of truth for all window operations.
@MainActor
@Observable
final class AppCoordinator {
    static let shared = AppCoordinator()

    // MARK: - Window References
    private var captureOverlayWindow: NSWindow?
    private var quickAccessPanel: NSPanel?
    private var annotationWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var floatingPins: [NSWindow] = []
    private var recordingBorderWindow: NSWindow?   // Click-through: just the border
    private var recordingToolbarPanel: NSPanel?     // Interactive: buttons
    private var stitcherWindow: NSWindow?
    private var screenDiffWindow: NSWindow?

    private init() {}

    // MARK: - Onboarding

    func showOnboarding() {
        let onboardingView = OnboardingView()
        let hostingView = NSHostingView(rootView: onboardingView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = "Welcome to SnapForge"
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        onboardingWindow = window
    }

    func dismissOnboarding() {
        onboardingWindow?.close()
        onboardingWindow = nil
        UserDefaults.standard.set(true, forKey: SettingsKey.hasCompletedOnboarding)
    }

    // MARK: - Capture Overlay

    func showCaptureOverlay(for mode: CaptureMode) {
        CaptureSessionManager.shared.startCapture(mode: mode)
    }

    func dismissCaptureOverlay() {
        CaptureSessionManager.shared.dismissOverlay()
    }

    // MARK: - Quick Access Overlay

    func showQuickAccess(image: NSImage, at point: NSPoint) {
        // Dismiss any existing panel first
        dismissQuickAccess()

        let quickAccessView = QuickAccessView(capturedImage: image)
        let hostingView = NSHostingView(rootView: quickAccessView)

        // Wrap in FirstMouseView so clicks work even when app is inactive
        let containerView = FirstMouseView()
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ])

        // Size the panel to fit all action buttons without clipping
        let panelWidth: CGFloat = 380
        let panelHeight: CGFloat = 220

        // Smart positioning: place the panel so the bottom-left corner
        // (Copy button) is nearest to the mouse for quick action.
        let toolbarHeight: CGFloat = 48
        let leftPadding: CGFloat = 10  // Small offset so cursor is near Copy button
        let idealX = point.x - leftPadding
        let idealY = point.y - toolbarHeight

        // Clamp to keep the panel fully on-screen
        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let clampedX = min(max(idealX, screenFrame.minX), screenFrame.maxX - panelWidth)
        let clampedY = min(max(idealY, screenFrame.minY), screenFrame.maxY - panelHeight)

        let panel = QuickAccessPanel(
            contentRect: NSRect(x: clampedX, y: clampedY, width: panelWidth, height: panelHeight),
            styleMask: [.titled, .closable, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.contentView = containerView
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.makeKeyAndOrderFront(nil)

        quickAccessPanel = panel
    }

    func dismissQuickAccess() {
        quickAccessPanel?.close()
        quickAccessPanel = nil
    }

    // MARK: - Annotation Editor

    func showAnnotationEditor(for image: NSImage) {
        let annotationView = AnnotationView(image: image)
        let hostingView = NSHostingView(rootView: annotationView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = "SnapForge Editor"
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        annotationWindow = window
    }

    func showBackgroundMockup(for image: NSImage) {
        let mockupView = BackgroundMockupView(
            sourceImage: image,
            onApply: { [weak self] compositeImage in
                self?.annotationWindow?.close()
                self?.showAnnotationEditor(for: compositeImage)
            },
            onCancel: { [weak self] in
                self?.annotationWindow?.close()
            }
        )
        let hostingView = NSHostingView(rootView: mockupView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 550),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = "Background & Mockup"
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Reuse annotationWindow reference for cleanup
        annotationWindow?.close()
        annotationWindow = window
    }

    // MARK: - Floating Pin

    func pinImage(_ image: NSImage, at frame: NSRect) {
        // Auto-size to image aspect ratio (max 400px wide)
        let maxWidth: CGFloat = 400
        let scale = min(1.0, maxWidth / image.size.width)
        let pinSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        let pinRect = NSRect(
            x: frame.origin.x,
            y: frame.origin.y,
            width: pinSize.width,
            height: pinSize.height
        )

        let panel = NSPanel(
            contentRect: pinRect,
            styleMask: [.closable, .resizable, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )

        // Create the view with close callback that captures THIS panel
        let pinView = FloatingPinView(
            image: image,
            onClose: { [weak self, weak panel] in
                guard let panel else { return }
                self?.removePin(panel)
            }
        )
        let hostingView = NSHostingView(rootView: pinView)

        panel.contentView = hostingView
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.makeKeyAndOrderFront(nil)

        floatingPins.append(panel)
    }

    func removePin(_ window: NSWindow) {
        window.close()
        floatingPins.removeAll { $0 === window }
    }

    // MARK: - Recording

    /// Pending recording rect (after area selection, before user clicks Record)
    private var pendingRecordingRect: CGRect?
    private var isGIFMode = false

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

    func dismissRecordingIndicator() {
        recordingBorderWindow?.close()
        recordingBorderWindow = nil
        recordingToolbarPanel?.close()
        recordingToolbarPanel = nil
    }

    // MARK: - Recording Countdown

    private var recordingCountdownWindow: NSWindow?

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

    // MARK: - History

    func showHistory() {
        // Re-show if already open
        if let existing = historyWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let historyView = NavigationStack { HistoryView() }
        let hostingView = NSHostingView(rootView: historyView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = "Capture History"
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        historyWindow = window
    }

    // MARK: - Stitcher

    func showStitcher(images: [NSImage]) {
        if let existing = stitcherWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let stitcherView = NavigationStack { StitcherView(images: images) }
        let hostingView = NSHostingView(rootView: stitcherView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = "Stitch Screenshots"
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        stitcherWindow = window
    }

    // MARK: - Screen Diff

    func showScreenDiff(imageA: NSImage?, imageB: NSImage?) {
        if let existing = screenDiffWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let diffView = ScreenDiffView(imageA: imageA, imageB: imageB)
        let hostingView = NSHostingView(rootView: diffView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = "Screen Diff"
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        screenDiffWindow = window
    }

    // MARK: - Cleanup

    func cleanup() {
        captureOverlayWindow?.close()
        quickAccessPanel?.close()
        annotationWindow?.close()
        onboardingWindow?.close()
        historyWindow?.close()
        stitcherWindow?.close()
        screenDiffWindow?.close()
        recordingBorderWindow?.close()
        recordingToolbarPanel?.close()
        floatingPins.forEach { $0.close() }
        floatingPins.removeAll()
    }
}
