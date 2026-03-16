import SwiftUI
import AppKit

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
/// Single source of truth for all window operations (Coordinator Pattern).
@MainActor
@Observable
final class AppCoordinator {
    static let shared = AppCoordinator()

    // MARK: - Window References
    private var captureOverlayWindow: NSWindow?
    private var quickAccessPanel: NSPanel?
    private var videoQuickAccessPanel: NSPanel?
    private var annotationWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var videoEditorWindow: NSWindow?
    private var floatingPins: [NSWindow] = []
    private var stitcherWindow: NSWindow?
    private var screenDiffWindow: NSWindow?

    private init() {
        // Observe window close to auto-revert activation policy
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            Task { @MainActor [weak self] in
                self?.handleWindowClosed(window)
            }
        }
    }

    // MARK: - Activation Policy

    /// Elevate to `.regular` so the app appears in Cmd+Tab.
    private func elevateActivationPolicy() {
        NSApp.setActivationPolicy(.regular)
    }

    /// Bring a window to front reliably, even when transitioning from .accessory mode.
    /// Order matters: elevate policy → activate app → make key → delayed safety net.
    private func bringWindowToFront(_ window: NSWindow) {
        elevateActivationPolicy()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        // Safety net: if macOS didn't honor the ordering (e.g. during policy transition),
        // force the window to front after a brief delay.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            if window.isVisible {
                window.orderFrontRegardless()
            }
        }
    }

    /// Revert to `.accessory` (menu-bar-only) when no user-facing windows remain visible.
    func revertActivationPolicyIfNeeded() {
        let hasVisibleWindows = [
            onboardingWindow, annotationWindow, historyWindow,
            videoEditorWindow, stitcherWindow, screenDiffWindow
        ].contains { $0?.isVisible == true }

        if !hasVisibleWindows {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Handle tracked window being closed — nil out reference and check policy.
    private func handleWindowClosed(_ window: NSWindow) {
        if window === onboardingWindow { onboardingWindow = nil }
        if window === annotationWindow { annotationWindow = nil }
        if window === historyWindow { historyWindow = nil }
        if window === videoEditorWindow { videoEditorWindow = nil }
        if window === stitcherWindow { stitcherWindow = nil }
        if window === screenDiffWindow { screenDiffWindow = nil }
        revertActivationPolicyIfNeeded()
    }

    // MARK: - Onboarding

    func showOnboarding() {
        let onboardingView = OnboardingView()
        let hostingView = NSHostingView(rootView: onboardingView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = "Welcome to SnapForge"
        window.center()
        window.isReleasedWhenClosed = false

        onboardingWindow = window
        bringWindowToFront(window)
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
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = .clear

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ])

        // Panel size: card content + SwiftUI .padding(24) for shadow clearance
        let shadowPadding: CGFloat = 24
        let panelWidth: CGFloat = 380 + shadowPadding * 2
        let panelHeight: CGFloat = 220 + shadowPadding * 2

        // Smart positioning: place the panel so the bottom-left corner
        // (Copy button) is nearest to the mouse for quick action.
        let toolbarHeight: CGFloat = 48
        let leftPadding: CGFloat = 10  // Small offset so cursor is near Copy button
        let idealX = point.x - leftPadding - shadowPadding
        let idealY = point.y - toolbarHeight - shadowPadding

        // Clamp to keep the panel fully on-screen
        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let clampedX = min(max(idealX, screenFrame.minX), screenFrame.maxX - panelWidth)
        let clampedY = min(max(idealY, screenFrame.minY), screenFrame.maxY - panelHeight)

        let panel = QuickAccessPanel(
            contentRect: NSRect(x: clampedX, y: clampedY, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
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
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.makeKeyAndOrderFront(nil)

        quickAccessPanel = panel
    }

    func dismissQuickAccess() {
        quickAccessPanel?.close()
        quickAccessPanel = nil
    }

    // MARK: - Video Quick Access Overlay

    func showVideoQuickAccess(videoURL: URL, at point: NSPoint) {
        dismissVideoQuickAccess()

        let quickAccessView = VideoQuickAccessView(videoURL: videoURL)
        let hostingView = NSHostingView(rootView: quickAccessView)

        let containerView = FirstMouseView()
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = .clear

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ])

        // Panel size: card content + SwiftUI .padding(24) for shadow clearance
        let shadowPadding: CGFloat = 24
        let panelWidth: CGFloat = 240 + shadowPadding * 2
        let panelHeight: CGFloat = 210 + shadowPadding * 2

        let toolbarHeight: CGFloat = 48
        let leftPadding: CGFloat = 10
        let idealX = point.x - leftPadding - shadowPadding
        let idealY = point.y - toolbarHeight - shadowPadding

        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let clampedX = min(max(idealX, screenFrame.minX), screenFrame.maxX - panelWidth)
        let clampedY = min(max(idealY, screenFrame.minY), screenFrame.maxY - panelHeight)

        // Borderless panel — no title bar, no HUD chrome
        let panel = QuickAccessPanel(
            contentRect: NSRect(x: clampedX, y: clampedY, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
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
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.makeKeyAndOrderFront(nil)

        videoQuickAccessPanel = panel
    }

    func dismissVideoQuickAccess() {
        videoQuickAccessPanel?.close()
        videoQuickAccessPanel = nil
    }

    // MARK: - Video Editor

    func showVideoEditor(for videoURL: URL) {
        if let existing = videoEditorWindow, existing.isVisible {
            bringWindowToFront(existing)
            return
        }

        let state = VideoEditorState(url: videoURL)
        let editorView = VideoEditorView(state: state)
        let hostingView = NSHostingView(rootView: editorView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = "Video Editor — \(videoURL.lastPathComponent)"
        window.center()
        window.isReleasedWhenClosed = false

        videoEditorWindow = window
        bringWindowToFront(window)
    }

    func dismissVideoEditor() {
        videoEditorWindow?.close()
        videoEditorWindow = nil
        revertActivationPolicyIfNeeded()
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

        annotationWindow = window
        bringWindowToFront(window)
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

        // Reuse annotationWindow reference for cleanup
        annotationWindow = window
        bringWindowToFront(window)
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

    // MARK: - Recording (delegated to RecordingCoordinator)

    func startRecording() {
        RecordingCoordinator.shared.startRecording()
    }

    func startFullscreenRecording() {
        RecordingCoordinator.shared.startFullscreenRecording()
    }

    func stopRecording() async {
        await RecordingCoordinator.shared.stopRecording()
    }

    func cancelRecording() async {
        await RecordingCoordinator.shared.cancelRecording()
    }

    func toggleRecording() {
        RecordingCoordinator.shared.toggleRecording()
    }

    func showRecordingIndicator(in rect: NSRect) {
        RecordingCoordinator.shared.showRecordingIndicator(in: rect)
    }

    func dismissRecordingIndicator() {
        RecordingCoordinator.shared.dismissRecordingIndicator()
    }

    // MARK: - History

    func showHistory() {
        // Re-show if already open
        if let existing = historyWindow, existing.isVisible {
            bringWindowToFront(existing)
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

        historyWindow = window
        bringWindowToFront(window)
    }

    // MARK: - Stitcher

    func showStitcher(images: [NSImage]) {
        if let existing = stitcherWindow, existing.isVisible {
            bringWindowToFront(existing)
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

        stitcherWindow = window
        bringWindowToFront(window)
    }

    // MARK: - Screen Diff

    func showScreenDiff(imageA: NSImage?, imageB: NSImage?) {
        if let existing = screenDiffWindow, existing.isVisible {
            bringWindowToFront(existing)
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

        screenDiffWindow = window
        bringWindowToFront(window)
    }

    // MARK: - Cleanup

    func cleanup() {
        captureOverlayWindow?.close()
        quickAccessPanel?.close()
        videoQuickAccessPanel?.close()
        annotationWindow?.close()
        onboardingWindow?.close()
        historyWindow?.close()
        videoEditorWindow?.close()
        stitcherWindow?.close()
        screenDiffWindow?.close()
        RecordingCoordinator.shared.cleanup()
        floatingPins.forEach { $0.close() }
        floatingPins.removeAll()
    }
}
