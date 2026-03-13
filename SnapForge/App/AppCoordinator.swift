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
    private var recordingIndicatorWindow: NSWindow?

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

    func startRecording() {
        // Use capture overlay to select recording area, then start recording
        let manager = CaptureSessionManager.shared
        manager.startRecordingAreaSelection { [weak self] rect in
            guard let self else { return }
            Task { @MainActor in
                await self.beginRecording(in: rect)
            }
        }
    }

    func startFullscreenRecording() {
        guard let screen = NSScreen.main else { return }
        Task { @MainActor in
            await beginRecording(in: screen.frame)
        }
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
            showRecordingIndicator(in: rect)
        } catch {
            print("❌ Recording failed: \(error)")
        }
    }

    func stopRecording() async {
        let recorder = ScreenRecordingService.shared
        if let savedURL = await recorder.stopRecording() {
            print("✅ Recording saved: \(savedURL.path)")
        }
        AppEnvironment.shared.isRecording = false
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
        let indicatorView = RecordingIndicatorView()
        let hostingView = NSHostingView(rootView: indicatorView)

        let window = NSWindow(
            contentRect: rect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = false
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        recordingIndicatorWindow = window
    }

    func dismissRecordingIndicator() {
        recordingIndicatorWindow?.close()
        recordingIndicatorWindow = nil
    }

    // MARK: - Cleanup

    func cleanup() {
        captureOverlayWindow?.close()
        quickAccessPanel?.close()
        annotationWindow?.close()
        onboardingWindow?.close()
        recordingIndicatorWindow?.close()
        floatingPins.forEach { $0.close() }
        floatingPins.removeAll()
    }
}
