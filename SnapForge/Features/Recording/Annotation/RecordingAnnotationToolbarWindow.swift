import AppKit
import SwiftUI

/// NSWindow popover hosting the annotation toolbar, anchored to the recording status bar.
/// Features an arrow indicator pointing toward the annotate button with auto above/below positioning.
@MainActor
final class RecordingAnnotationToolbarWindow: NSWindow {
    private let state: RecordingAnnotationState
    private weak var anchorWindow: NSWindow?
    private var anchorButtonCenterX: CGFloat = 0
    private let arrowView = RecordingAnnotationPopoverArrowView()
    private let popoverGap: CGFloat = 6

    init(state: RecordingAnnotationState) {
        self.state = state
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        buildContent()
    }

    private func buildContent() {
        let toolbarView = RecordingAnnotationToolbarView(state: state)
        let hostingView = FirstMouseHostingView(rootView: toolbarView)
        let bodySize = hostingView.fittingSize
        let arrowH = RecordingAnnotationPopoverArrowView.arrowHeight
        let totalHeight = bodySize.height + arrowH

        // Container holds effect view + arrow
        let container = NSView(frame: NSRect(origin: .zero, size: CGSize(width: bodySize.width, height: totalHeight)))
        container.wantsLayer = true

        // Effect view (body)
        let effectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: bodySize.width, height: bodySize.height))
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 8
        effectView.layer?.masksToBounds = true

        hostingView.frame = effectView.bounds
        hostingView.autoresizingMask = [.width, .height]
        effectView.addSubview(hostingView)

        // Arrow view
        arrowView.frame = NSRect(x: 0, y: bodySize.height, width: bodySize.width, height: arrowH)
        arrowView.arrowEdge = .top

        container.addSubview(effectView)
        container.addSubview(arrowView)

        contentView = container
        setContentSize(CGSize(width: bodySize.width, height: totalHeight))
    }

    /// Set anchor window and button position for smart positioning
    func setAnchor(window: NSWindow, buttonCenterX: CGFloat) {
        anchorWindow = window
        anchorButtonCenterX = buttonCenterX
        positionRelativeToAnchor()
        window.addChildWindow(self, ordered: .above)
    }

    func positionRelativeToAnchor() {
        guard let anchor = anchorWindow else { return }
        let anchorFrame = anchor.frame
        let size = frame.size
        let arrowEdge = computeArrowEdge()
        let arrowH = RecordingAnnotationPopoverArrowView.arrowHeight
        let bodyH = size.height - arrowH

        // X: center on annotate button
        var x = anchorButtonCenterX - size.width / 2
        if let screen = anchor.screen ?? NSScreen.main {
            let sf = screen.visibleFrame
            x = max(sf.minX + 4, min(x, sf.maxX - size.width - 4))
        }

        // Update arrow
        arrowView.arrowCenterX = anchorButtonCenterX - x
        arrowView.arrowEdge = arrowEdge

        // Rearrange subviews based on arrow edge
        if let container = contentView {
            let effectView = container.subviews.first(where: { $0 is NSVisualEffectView })
            switch arrowEdge {
            case .top:
                // Arrow at top, body at bottom → popover below anchor
                effectView?.frame.origin.y = 0
                arrowView.frame.origin.y = bodyH
            case .bottom:
                // Arrow at bottom, body at top → popover above anchor
                effectView?.frame.origin.y = arrowH
                arrowView.frame.origin.y = 0
            }
        }

        // Y positioning
        let y: CGFloat
        switch arrowEdge {
        case .top:
            // Popover below: arrow tip touches anchor bottom
            y = anchorFrame.origin.y - size.height - popoverGap
        case .bottom:
            // Popover above: arrow tip touches anchor top
            y = anchorFrame.maxY + popoverGap
        }

        setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func computeArrowEdge() -> AnnotationPopoverArrowEdge {
        guard let anchor = anchorWindow, let screen = anchor.screen ?? NSScreen.main else { return .bottom }
        // If anchor is in top half of screen → popover below (arrow up)
        // If anchor is in bottom half → popover above (arrow down)
        return anchor.frame.midY > screen.visibleFrame.midY ? .top : .bottom
    }

    override func close() {
        // Detach from parent before closing
        if let parent = parent {
            parent.removeChildWindow(self)
        }
        super.close()
    }
}
