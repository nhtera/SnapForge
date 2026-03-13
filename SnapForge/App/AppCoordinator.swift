import SwiftUI
import AppKit

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
    private var floatingPins: [NSWindow] = []
    private var recordingBorderWindow: NSWindow?   // Click-through: just the border
    private var recordingToolbarPanel: NSPanel?     // Interactive: buttons

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
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
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
        let quickAccessView = QuickAccessView(capturedImage: image)
        let hostingView = NSHostingView(rootView: quickAccessView)

        let panel = NSPanel(
            contentRect: NSRect(x: point.x, y: point.y, width: 320, height: 200),
            styleMask: [.titled, .closable, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
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

    // MARK: - Floating Pin

    func pinImage(_ image: NSImage, at frame: NSRect) {
        let pinView = FloatingPinView(image: image)
        let hostingView = NSHostingView(rootView: pinView)

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.makeKeyAndOrderFront(nil)

        floatingPins.append(panel)
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
        let recorder = ScreenRecordingService.shared
        let storage = AppEnvironment.shared.storageService

        do {
            try await recorder.prepareRecording(
                rect: rect,
                format: .mov,
                quality: .high,
                fps: UserDefaults.standard.integer(forKey: "recordingFPS"),
                captureSystemAudio: true,
                captureMicrophone: false,
                saveDirectory: storage.snapForgeDirectory
            )
            try await recorder.startRecording()

            AppEnvironment.shared.isRecording = true
            pendingRecordingRect = nil

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
        dismissRecordingIndicator()
    }

    private func convertToGIF(videoURL: URL) async {
        let encoder = GIFEncoder()
        let gifURL = videoURL.deletingPathExtension().appendingPathExtension("gif")
        let config = GIFEncoder.Configuration(fps: 10, maxWidth: 640, quality: 0.8)
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

        // 2. Toolbar panel — non-activating, accepts first mouse
        let toolbarView = RecordingToolbarView()
        showToolbarPanel(toolbarView: toolbarView, cocoaRect: cocoaRect)
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

    // MARK: - Cleanup

    func cleanup() {
        captureOverlayWindow?.close()
        quickAccessPanel?.close()
        annotationWindow?.close()
        onboardingWindow?.close()
        recordingBorderWindow?.close()
        recordingToolbarPanel?.close()
        floatingPins.forEach { $0.close() }
        floatingPins.removeAll()
    }
}
