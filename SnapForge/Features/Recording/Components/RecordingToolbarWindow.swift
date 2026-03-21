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

    // MARK: - Edge Snapping

    private static let snapThreshold: CGFloat = 20

    /// Save toolbar position after drag for restoration on next recording
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        guard isMovableByWindowBackground else { return }
        snapToEdgesIfNeeded()
        saveToolbarPosition()
    }

    /// Snap toolbar to nearest screen edge if within threshold
    private func snapToEdgesIfNeeded() {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        var origin = frame.origin
        let threshold = Self.snapThreshold

        // Snap to left/right edge
        if abs(origin.x - screen.minX) < threshold {
            origin.x = screen.minX + 4
        } else if abs(origin.x + frame.width - screen.maxX) < threshold {
            origin.x = screen.maxX - frame.width - 4
        }

        // Snap to top/bottom edge
        if abs(origin.y - screen.minY) < threshold {
            origin.y = screen.minY + 4
        } else if abs(origin.y + frame.height - screen.maxY) < threshold {
            origin.y = screen.maxY - frame.height - 4
        }

        if origin != frame.origin {
            setFrameOrigin(origin)
        }
    }

    /// Persist toolbar position for next session
    private func saveToolbarPosition() {
        let pos: [String: Double] = ["x": frame.origin.x, "y": frame.origin.y]
        UserDefaults.standard.set(pos, forKey: SettingsKey.recordingToolbarPosition)
    }

    /// Restore saved toolbar position if available
    func restoreSavedPosition() {
        guard let pos = UserDefaults.standard.dictionary(forKey: SettingsKey.recordingToolbarPosition),
              let x = pos["x"] as? Double, let y = pos["y"] as? Double else { return }
        let point = CGPoint(x: x, y: y)
        // Only restore if point is on a visible screen
        if NSScreen.screens.contains(where: { $0.visibleFrame.contains(point) }) {
            setFrameOrigin(point)
        }
    }

    /// Set the SwiftUI content and compute intrinsic size.
    /// Uses native NSVisualEffectView(.hudWindow) for macOS-native frosted glass appearance.
    func setContent<V: View>(_ view: V, draggable: Bool = false) {
        isMovableByWindowBackground = draggable

        let styledView = view
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .environment(\.colorScheme, .dark)

        let hostingView = FirstMouseHostingView(rootView: styledView)
        contentSize = hostingView.fittingSize

        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: contentSize))
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = RecordingToolbarConstants.toolbarCornerRadius
        effectView.layer?.masksToBounds = true

        hostingView.frame = effectView.bounds
        hostingView.autoresizingMask = [.width, .height]
        effectView.addSubview(hostingView)
        contentView = effectView

        hasShadow = true
    }

    /// Crossfade to new content: fade out old → swap + resize → fade in new.
    /// Used for smooth pre-record → recording toolbar transition without window flicker.
    func animateContentSwap<V: View>(_ view: V, draggable: Bool = false, belowRect: CGRect? = nil) {
        isMovableByWindowBackground = draggable

        let styledView = view
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .environment(\.colorScheme, .dark)

        let newHostingView = FirstMouseHostingView(rootView: styledView)
        let newSize = newHostingView.fittingSize

        let newEffectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: newSize))
        newEffectView.material = .hudWindow
        newEffectView.blendingMode = .behindWindow
        newEffectView.state = .active
        newEffectView.wantsLayer = true
        newEffectView.layer?.cornerRadius = RecordingToolbarConstants.toolbarCornerRadius
        newEffectView.layer?.masksToBounds = true

        newHostingView.frame = newEffectView.bounds
        newHostingView.autoresizingMask = [.width, .height]
        newEffectView.addSubview(newHostingView)

        let targetFrame: NSRect
        if let belowRect {
            targetFrame = Self.computeFrameBelowRect(belowRect, toolbarSize: newSize)
        } else {
            targetFrame = NSRect(
                x: frame.midX - newSize.width / 2,
                y: frame.midY - newSize.height / 2,
                width: newSize.width, height: newSize.height
            )
        }

        let oldContent = contentView
        oldContent?.wantsLayer = true
        contentSize = newSize

        // Phase 1: Fade out old content
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            oldContent?.animator().alphaValue = 0
        }, completionHandler: { [self] in
            // Phase 2: Swap content + resize
            contentView = newEffectView
            newEffectView.alphaValue = 0
            setFrame(targetFrame, display: true)
            hasShadow = true
            // Phase 3: Fade in new content
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                newEffectView.animator().alphaValue = 1
            })
        })
    }

    /// Position toolbar below a given rect (in Cocoa screen coords)
    func positionBelowRect(_ cocoaRect: CGRect) {
        setFrame(Self.computeFrameBelowRect(cocoaRect, toolbarSize: contentSize), display: true)
    }

    /// Shared positioning logic: compute frame below a Cocoa rect with smart fallback
    static func computeFrameBelowRect(_ cocoaRect: CGRect, toolbarSize: CGSize) -> CGRect {
        let gap = RecordingToolbarConstants.toolbarGap
        let visibleFrame =
            NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let minSafeY = visibleFrame.origin.y
        let maxSafeY = visibleFrame.maxY

        let belowY = cocoaRect.origin.y - toolbarSize.height - gap
        let insideBottomY = max(cocoaRect.origin.y + gap, minSafeY + gap)
        let aboveY = cocoaRect.maxY + gap

        let toolbarY: CGFloat
        if belowY >= minSafeY {
            toolbarY = belowY
        } else if insideBottomY + toolbarSize.height <= cocoaRect.maxY {
            toolbarY = insideBottomY
        } else if aboveY + toolbarSize.height <= maxSafeY {
            toolbarY = aboveY
        } else {
            toolbarY = visibleFrame.midY - toolbarSize.height / 2
        }

        return CGRect(
            x: cocoaRect.midX - toolbarSize.width / 2,
            y: toolbarY,
            width: toolbarSize.width,
            height: toolbarSize.height
        )
    }
}
