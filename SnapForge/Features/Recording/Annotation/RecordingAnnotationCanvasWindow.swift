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
        // Between recording border (.statusBar) and toolbar (.statusBar + 1)
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
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
