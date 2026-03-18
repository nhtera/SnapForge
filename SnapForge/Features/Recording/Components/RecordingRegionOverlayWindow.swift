import AppKit

/// Full-screen transparent window hosting the interactive region overlay during pre-record.
/// Dynamically toggles `ignoresMouseEvents` so clicks outside the selection pass through.
@MainActor
final class RecordingRegionOverlayWindow: NSWindow {
    let overlayView: RecordingRegionOverlayView
    private let regionState: RecordingRegionState
    private nonisolated(unsafe) var mouseTracker: Any?
    private nonisolated(unsafe) var localMouseTracker: Any?

    init(screen: NSScreen, state: RecordingRegionState) {
        overlayView = RecordingRegionOverlayView(state: state)
        regionState = state

        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        contentView = overlayView
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary]

        // Track global mouse moves to toggle click-through dynamically
        mouseTracker = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.updateIgnoresMouseEvents()
        }
        localMouseTracker = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.updateIgnoresMouseEvents()
            return event
        }
    }

    override var canBecomeKey: Bool { true }

    /// Toggle ignoresMouseEvents based on whether cursor is near the selection
    private func updateIgnoresMouseEvents() {
        let mouseScreen = NSEvent.mouseLocation
        let mouseWindow = CGPoint(
            x: mouseScreen.x - frame.origin.x,
            y: mouseScreen.y - frame.origin.y
        )
        let hitArea = regionState.rect.insetBy(dx: -24, dy: -24)
        let shouldIgnore = !hitArea.contains(mouseWindow)

        if ignoresMouseEvents != shouldIgnore {
            ignoresMouseEvents = shouldIgnore
        }
    }

    deinit {
        if let t = mouseTracker { NSEvent.removeMonitor(t) }
        if let t = localMouseTracker { NSEvent.removeMonitor(t) }
    }
}
