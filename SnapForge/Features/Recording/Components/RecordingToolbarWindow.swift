import AppKit
import SwiftUI

/// NSWindow wrapper for recording toolbars.
/// Uses .popUpMenu level to stay above annotation canvas and receive clicks properly.
@MainActor
final class RecordingToolbarWindow: NSWindow {
    private var contentSize: CGSize = .zero

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // Above canvas (.floating+1) and border (.floating) — matches Snapzy
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    /// Set the SwiftUI content and compute intrinsic size
    func setContent<V: View>(_ view: V, draggable: Bool = false) {
        isMovableByWindowBackground = draggable

        // Wrap content with dark material background and rounded corners in SwiftUI
        let styledView =
            view
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 12))
            .environment(\.colorScheme, .dark)

        let hostingView = FirstMouseHostingView(rootView: styledView)
        contentSize = hostingView.fittingSize
        contentView = hostingView

        hasShadow = true
    }

    /// Position toolbar below a given rect (in CG screen coords, converted to Cocoa)
    func positionBelowRect(_ cocoaRect: CGRect) {
        let size = contentSize
        let gap = RecordingToolbarConstants.toolbarGap
        let visibleFrame =
            NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let minSafeY = visibleFrame.origin.y
        let maxSafeY = visibleFrame.maxY

        let belowY = cocoaRect.origin.y - size.height - gap
        let insideBottomY = max(cocoaRect.origin.y + gap, minSafeY + gap)
        let aboveY = cocoaRect.maxY + gap

        let toolbarY: CGFloat
        if belowY >= minSafeY {
            toolbarY = belowY
        } else if insideBottomY + size.height <= cocoaRect.maxY {
            toolbarY = insideBottomY
        } else if aboveY + size.height <= maxSafeY {
            toolbarY = aboveY
        } else {
            toolbarY = visibleFrame.midY - size.height / 2
        }

        let toolbarRect = CGRect(
            x: cocoaRect.midX - size.width / 2,
            y: toolbarY,
            width: size.width,
            height: size.height
        )
        setFrame(toolbarRect, display: true)
    }
}
