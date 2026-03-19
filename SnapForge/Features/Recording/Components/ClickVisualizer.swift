import AppKit
import QuartzCore

// MARK: - Click Visualizer (Service Layer)

/// Detects global mouse clicks and forwards events to the overlay window.
/// Uses NSEvent.mouseLocation for reliable screen-space coordinates.
@MainActor
@Observable
final class ClickVisualizer {
    static let shared = ClickVisualizer()

    private var globalDownMonitor: Any?
    private var localDownMonitor: Any?
    private var globalUpMonitor: Any?
    private var localUpMonitor: Any?
    private var globalDragMonitor: Any?
    private var localDragMonitor: Any?

    private var overlayWindow: ClickHighlightOverlayWindow?
    private var isMouseDown = false
    private(set) var isActive = false

    /// Start click visualization for a given recording area.
    /// The overlay window is included in the recording via SCStream exceptingWindows.
    func start(recordingRect: CGRect = NSScreen.main?.frame ?? .zero) {
        guard !isActive else { return }
        isActive = true

        let config = ClickHighlightConfiguration()
        let window = ClickHighlightOverlayWindow(recordingRect: recordingRect, config: config)
        window.orderFrontRegardless()
        overlayWindow = window

        // Mouse-down: show ripple + hold circle
        globalDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMouseDown() }
        }
        localDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleMouseDown() }
            return event
        }

        // Mouse-up: dismiss hold circle
        globalUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMouseUp() }
        }
        localUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleMouseUp() }
            return event
        }

        // Mouse-dragged: move hold circle
        globalDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .rightMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMouseDragged() }
        }
        localDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleMouseDragged() }
            return event
        }
    }

    func stop() {
        let monitors = [globalDownMonitor, localDownMonitor, globalUpMonitor, localUpMonitor, globalDragMonitor, localDragMonitor]
        for m in monitors { if let m { NSEvent.removeMonitor(m) } }
        globalDownMonitor = nil; localDownMonitor = nil
        globalUpMonitor = nil; localUpMonitor = nil
        globalDragMonitor = nil; localDragMonitor = nil
        overlayWindow?.close()
        overlayWindow = nil
        isMouseDown = false
        isActive = false
    }

    /// Window ID for adding to SCStream exceptingWindows (makes effect visible in recording)
    var overlayWindowID: Int? {
        overlayWindow.map { Int($0.windowNumber) }
    }

    private func handleMouseDown() {
        let location = NSEvent.mouseLocation
        // Skip click effects on toolbar windows (recording/annotation toolbars at .popUpMenu)
        for window in NSApp.windows where window.isVisible && window.level >= .popUpMenu {
            if window.frame.contains(location) { return }
        }
        isMouseDown = true
        overlayWindow?.showClickEffect(at: location)
    }

    private func handleMouseUp() {
        guard isMouseDown else { return }
        isMouseDown = false
        overlayWindow?.dismissClickEffect()
    }

    private func handleMouseDragged() {
        guard isMouseDown else { return }
        overlayWindow?.moveClickEffect(to: NSEvent.mouseLocation)
    }
}

// MARK: - Overlay Window

/// Single transparent overlay window sized to the recording area.
/// Captured by SCStream via exceptingWindows so click effects appear in recordings.
@MainActor
private final class ClickHighlightOverlayWindow: NSWindow {
    private var holdCircleView: ClickHoldCircleView?
    private let config: ClickHighlightConfiguration

    init(recordingRect: CGRect, config: ClickHighlightConfiguration) {
        self.config = config
        super.init(contentRect: recordingRect, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private func viewPoint(from screenPoint: NSPoint) -> NSPoint {
        convertPoint(fromScreen: screenPoint)
    }

    func showClickEffect(at screenPoint: NSPoint) {
        guard let contentView else { return }
        let pt = viewPoint(from: screenPoint)

        // Spawn ripple(s) with staggered delays
        for i in 0..<config.rippleCount {
            let delay = Double(i) * 0.08
            let ripple = ClickRippleView(center: pt, config: config)
            contentView.addSubview(ripple)
            if delay > 0 {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(delay))
                    ripple.animateExpandAndFade { [weak ripple] in ripple?.removeFromSuperview() }
                }
            } else {
                ripple.animateExpandAndFade { [weak ripple] in ripple?.removeFromSuperview() }
            }
        }

        // Persistent hold circle while mouse is held
        holdCircleView?.removeFromSuperview()
        let hold = ClickHoldCircleView(center: pt, config: config)
        contentView.addSubview(hold)
        hold.animateIn()
        holdCircleView = hold
    }

    func moveClickEffect(to screenPoint: NSPoint) {
        let pt = viewPoint(from: screenPoint)
        holdCircleView?.updateCenter(pt)
    }

    func dismissClickEffect() {
        guard let hold = holdCircleView else { return }
        holdCircleView = nil
        hold.animateOut { [weak hold] in hold?.removeFromSuperview() }
    }
}
