import AppKit

/// Transparent NSWindow hosting the annotation canvas during recording.
/// Starts click-through (selection mode); enables mouse events only when a drawing tool is active.
@MainActor
final class RecordingAnnotationCanvasWindow: NSWindow {
    let canvasView: RecordingAnnotationCanvasView
    private var observerTask: Task<Void, Never>?

    init(frame: CGRect, state: RecordingAnnotationState) {
        canvasView = RecordingAnnotationCanvasView(state: state)
        state.canvasView = canvasView

        super.init(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        contentView = canvasView
        // Between border (.floating) and toolbars (.popUpMenu) — matches Snapzy
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Start click-through; enable when drawing tool selected
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Observe tool changes to toggle mouse event handling
        observerTask = Task { [weak self] in
            var lastTool: AnnotationToolType = .selection
            while !Task.isCancelled {
                let tool = state.selectedTool
                if tool != lastTool {
                    let wasTool = lastTool
                    lastTool = tool
                    // Dismiss active text field when switching away from text tool
                    if wasTool == .text {
                        self?.canvasView.dismissTextOverlay()
                    }
                    let isSelection = (tool == .selection)
                    self?.ignoresMouseEvents = isSelection
                    if !isSelection {
                        self?.makeKeyAndOrderFront(nil)
                        self?.makeFirstResponder(self?.canvasView)
                    }
                    // Update cursor for new tool
                    self?.canvasView.updateCursorForTool()
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func close() {
        observerTask?.cancel()
        observerTask = nil
        super.close()
    }

    var cgWindowID: CGWindowID { CGWindowID(windowNumber) }
}
