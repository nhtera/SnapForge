import AppKit

/// Transparent NSWindow hosting the annotation canvas during recording
@MainActor
final class RecordingAnnotationCanvasWindow: NSWindow {
    let canvasView: RecordingAnnotationCanvasView

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
        level = .statusBar + 2
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary]
    }

    override var canBecomeKey: Bool { true }

    /// Window number for SCStream filter
    var cgWindowID: CGWindowID {
        CGWindowID(windowNumber)
    }
}
