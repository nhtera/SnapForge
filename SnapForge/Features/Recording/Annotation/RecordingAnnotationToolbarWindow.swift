import AppKit
import SwiftUI

/// NSWindow popover hosting the annotation toolbar, anchored to the recording status bar.
/// Uses .popUpMenu level to stay above annotation canvas and receive clicks properly.
@MainActor
final class RecordingAnnotationToolbarWindow: NSWindow {
    private let state: RecordingAnnotationState
    private weak var anchorWindow: NSWindow?
    private var anchorButtonCenterX: CGFloat = 0

    init(state: RecordingAnnotationState) {
        self.state = state
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // Above canvas (.floating+1) — matches Snapzy
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let toolbarView = RecordingAnnotationToolbarView(state: state)
        let hostingView = FirstMouseHostingView(rootView: toolbarView)
        let size = hostingView.fittingSize

        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 8
        effectView.layer?.masksToBounds = true

        hostingView.frame = effectView.bounds
        hostingView.autoresizingMask = [.width, .height]
        effectView.addSubview(hostingView)
        contentView = effectView

        setContentSize(size)
    }

    /// Set anchor window and button position for smart positioning
    func setAnchor(window: NSWindow, buttonCenterX: CGFloat) {
        anchorWindow = window
        anchorButtonCenterX = buttonCenterX
        positionRelativeToAnchor()
        // Attach as child window for zero-lag movement
        window.addChildWindow(self, ordered: .above)
    }

    func positionRelativeToAnchor() {
        guard let anchor = anchorWindow else { return }
        let anchorFrame = anchor.frame
        let size = frame.size

        // Center on anchor button, position above the toolbar
        let x = anchorButtonCenterX - size.width / 2
        let y = anchorFrame.maxY + 8

        // Clamp to screen
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let clampedX = max(screenFrame.minX, min(x, screenFrame.maxX - size.width))
        let clampedY = min(y, screenFrame.maxY - size.height)

        setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
    }
}
