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
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Start click-through; enable when drawing tool selected
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary]

        // Observe tool changes to toggle mouse event handling
        observerTask = Task { [weak self] in
            var lastTool: AnnotationToolType = .selection
            while !Task.isCancelled {
                let tool = state.selectedTool
                if tool != lastTool {
                    lastTool = tool
                    // Selection mode = click-through; drawing tools = accept mouse
                    self?.ignoresMouseEvents = (tool == .selection)
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    override var canBecomeKey: Bool { true }

    override func close() {
        observerTask?.cancel()
        observerTask = nil
        super.close()
    }

    var cgWindowID: CGWindowID { CGWindowID(windowNumber) }
}
