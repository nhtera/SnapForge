import AppKit

/// Manages annotation canvas and toolbar windows during recording
@MainActor
final class RecordingAnnotationManager {
    private(set) var annotationState: RecordingAnnotationState?
    private var canvasWindow: RecordingAnnotationCanvasWindow?
    private var toolbarWindow: RecordingAnnotationToolbarWindow?
    private var observerTask: Task<Void, Never>?
    private let shortcutMonitor = RecordingAnnotationShortcutMonitor()

    /// Create annotation state and start observing toggle
    /// - Parameters:
    ///   - anchorPanel: Toolbar panel for positioning annotation toolbar
    ///   - cocoaRect: Recording area in Cocoa coordinates (for canvas window frame)
    func setup(anchorPanel: RecordingToolbarWindow?, cocoaRect: CGRect) {
        let state = RecordingAnnotationState()
        annotationState = state
        self.anchorPanel = anchorPanel
        self.canvasCocoaRect = cocoaRect

        observerTask?.cancel()
        observerTask = Task { [weak self] in
            var wasEnabled = false
            while !Task.isCancelled {
                let isEnabled = self?.annotationState?.isAnnotationEnabled ?? false
                if isEnabled != wasEnabled {
                    wasEnabled = isEnabled
                    if isEnabled {
                        self?.showAnnotationUI()
                    } else {
                        self?.hideUI()
                    }
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private var anchorPanel: RecordingToolbarWindow?
    private var canvasCocoaRect: CGRect = .zero

    /// Show canvas and toolbar windows
    private func showAnnotationUI() {
        guard let annState = annotationState else { return }
        let cocoaRect = canvasCocoaRect

        let canvas = RecordingAnnotationCanvasWindow(frame: cocoaRect, state: annState)
        canvas.makeKeyAndOrderFront(nil)
        canvasWindow = canvas

        let toolbar = RecordingAnnotationToolbarWindow(state: annState)
        if let panel = anchorPanel {
            toolbar.setAnchor(window: panel, buttonCenterX: panel.frame.midX)
        }
        toolbar.orderFrontRegardless()
        toolbarWindow = toolbar

        annState.startCleanupTimer()
        shortcutMonitor.start(state: annState)

        Task {
            await ScreenRecordingService.shared.addExceptedWindows([canvas.windowNumber])
        }
    }

    /// Hide canvas and toolbar windows
    private func hideUI() {
        canvasWindow?.close()
        canvasWindow = nil
        toolbarWindow?.close()
        toolbarWindow = nil
        annotationState?.stopCleanupTimer()
        annotationState?.laserPointerState.stopRefreshTimer()
        shortcutMonitor.stop()
    }

    /// Update the anchor panel reference without recreating state
    func updateAnchorPanel(_ panel: RecordingToolbarWindow) {
        self.anchorPanel = panel
        toolbarWindow?.setAnchor(window: panel, buttonCenterX: panel.frame.midX)
    }

    /// Tear down everything
    func dismiss() {
        observerTask?.cancel()
        observerTask = nil
        hideUI()
        annotationState = nil
    }
}
