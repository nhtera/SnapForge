import AppKit

/// Full-screen transparent window hosting the interactive region overlay during pre-record
@MainActor
final class RecordingRegionOverlayWindow: NSWindow {
    let overlayView: RecordingRegionOverlayView

    init(screen: NSScreen, state: RecordingRegionState) {
        overlayView = RecordingRegionOverlayView(state: state)

        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        contentView = overlayView
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary]
    }

    override var canBecomeKey: Bool { true }
}
