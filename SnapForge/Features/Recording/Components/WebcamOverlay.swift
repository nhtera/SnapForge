import SwiftUI
import AVFoundation
import AppKit

/// Floating webcam overlay for screen recording — shows camera feed in a draggable circle.
@MainActor
@Observable
final class WebcamOverlayManager: NSObject {
    private var panel: NSPanel?
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    var isVisible = false
    var diameter: CGFloat = 150
    var opacity: Double = 1.0
    var shape: OverlayShape = .circle
    /// Recording area rect (Cocoa coords) for corner snapping
    var recordingCocoaRect: CGRect = .zero

    enum OverlayShape {
        case circle, roundedRect
    }

    enum CornerPosition: Int, CaseIterable {
        case topLeft = 0, topRight, bottomLeft, bottomRight

        var label: String {
            switch self {
            case .topLeft: return "Top Left"
            case .topRight: return "Top Right"
            case .bottomLeft: return "Bottom Left"
            case .bottomRight: return "Bottom Right"
            }
        }
    }

    // MARK: - Show/Hide

    func show(insideRect cocoaRect: CGRect? = nil) {
        guard panel == nil else { return }

        let session = AVCaptureSession()
        session.sessionPreset = .medium

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            AppLogger.recording.warning("No front camera available for webcam overlay")
            return
        }

        if session.canAddInput(input) { session.addInput(input) }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill

        let size = diameter
        if let rect = cocoaRect { recordingCocoaRect = rect }
        let panelFrame = computeInitialFrame(size: size, cocoaRect: cocoaRect)

        let overlayPanel = NSPanel(
            contentRect: panelFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        // Above region overlay (.floating) and recording border (.statusBar)
        overlayPanel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        overlayPanel.isOpaque = false
        overlayPanel.backgroundColor = .clear
        overlayPanel.hasShadow = true
        overlayPanel.isMovableByWindowBackground = true
        overlayPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let contentView = WebcamContentView(frame: panelFrame)
        contentView.manager = self
        contentView.wantsLayer = true
        let radius = cornerRadius(for: shape, diameter: size)
        contentView.layer?.cornerRadius = radius
        contentView.layer?.masksToBounds = true
        contentView.layer?.borderColor = NSColor.white.withAlphaComponent(0.6).cgColor
        contentView.layer?.borderWidth = 3

        preview.frame = contentView.bounds
        preview.cornerRadius = radius
        contentView.layer?.addSublayer(preview)

        overlayPanel.contentView = contentView
        overlayPanel.alphaValue = CGFloat(opacity)
        overlayPanel.orderFrontRegardless()
        session.startRunning()

        self.panel = overlayPanel
        self.captureSession = session
        self.previewLayer = preview
        self.isVisible = true
    }

    func hide() {
        captureSession?.stopRunning()
        captureSession = nil
        previewLayer = nil
        panel?.orderOut(nil)
        panel = nil
        isVisible = false
    }

    var overlayWindowID: Int? { panel.map { Int($0.windowNumber) } }
    func toggle() { isVisible ? hide() : show() }

    // MARK: - Controls

    func updateOpacity(_ value: Double) {
        opacity = value
        panel?.alphaValue = CGFloat(value)
    }

    func updateSize(_ newDiameter: CGFloat) {
        let clamped = max(80, min(300, newDiameter))
        diameter = clamped
        guard let panel = panel, let contentView = panel.contentView else { return }
        var frame = panel.frame
        frame.size = NSSize(width: clamped, height: clamped)
        panel.setFrame(frame, display: true)
        let radius = cornerRadius(for: shape, diameter: clamped)
        contentView.layer?.cornerRadius = radius
        previewLayer?.frame = contentView.bounds
        previewLayer?.cornerRadius = radius
    }

    func updateShape(_ newShape: OverlayShape) {
        shape = newShape
        guard let panel = panel, let contentView = panel.contentView else { return }
        let radius = cornerRadius(for: newShape, diameter: diameter)

        // Update all layers — content view, preview, and sublayers
        contentView.layer?.cornerRadius = radius
        previewLayer?.cornerRadius = radius

        // Also update the border on all sublayers that might cache the old shape
        for sublayer in contentView.layer?.sublayers ?? [] {
            sublayer.cornerRadius = radius
        }

        // Force complete visual update
        contentView.layer?.setNeedsDisplay()
        contentView.needsDisplay = true
        panel.invalidateShadow()
        panel.display()
    }

    func snapToCorner(_ corner: CornerPosition) {
        guard let panel = panel else { return }
        // Use recording rect if available, otherwise fall back to screen
        let r: CGRect
        if !recordingCocoaRect.isEmpty && recordingCocoaRect.width > 10 {
            r = recordingCocoaRect
        } else {
            r = NSScreen.main?.visibleFrame ?? .zero
        }
        let padding: CGFloat = 16
        let size = diameter
        let origin: CGPoint
        switch corner {
        case .topLeft:     origin = CGPoint(x: r.minX + padding, y: r.maxY - size - padding)
        case .topRight:    origin = CGPoint(x: r.maxX - size - padding, y: r.maxY - size - padding)
        case .bottomLeft:  origin = CGPoint(x: r.minX + padding, y: r.minY + padding)
        case .bottomRight: origin = CGPoint(x: r.maxX - size - padding, y: r.minY + padding)
        }
        panel.setFrameOrigin(origin)
    }

    // MARK: - Private

    private func cornerRadius(for shape: OverlayShape, diameter: CGFloat) -> CGFloat {
        shape == .circle ? diameter / 2 : 16
    }

    private func computeInitialFrame(size: CGFloat, cocoaRect: CGRect?) -> NSRect {
        if let rect = cocoaRect {
            return NSRect(x: rect.origin.x + 16, y: rect.origin.y + 16, width: size, height: size)
        }
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        return NSRect(x: screenFrame.maxX - size - 20, y: screenFrame.minY + 20, width: size, height: size)
    }
}

// MARK: - WebcamContentView (resize handle, context menu, shape toggle)

private class WebcamContentView: NSView {
    weak var manager: WebcamOverlayManager?
    private var isHovered = false
    private var isResizing = false
    private var resizeStartPoint: CGPoint = .zero
    private var resizeStartDiameter: CGFloat = 0

    override var mouseDownCanMoveWindow: Bool { !isResizing }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self, userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }

    // MARK: - Resize Handle Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isHovered else { return }
        let handleSize: CGFloat = 12
        let path = NSBezierPath()
        path.move(to: CGPoint(x: bounds.maxX - 2, y: 2))
        path.line(to: CGPoint(x: bounds.maxX - 2, y: 2 + handleSize))
        path.line(to: CGPoint(x: bounds.maxX - 2 - handleSize, y: 2))
        path.close()
        NSColor.white.withAlphaComponent(0.6).setFill()
        path.fill()
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            // Double-click: toggle shape
            guard let manager = manager else { return }
            let newShape: WebcamOverlayManager.OverlayShape = (manager.shape == .circle) ? .roundedRect : .circle
            manager.updateShape(newShape)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let handleHitSize: CGFloat = 24
        let handleHitRect = CGRect(x: bounds.maxX - handleHitSize, y: 0, width: handleHitSize, height: handleHitSize)
        if handleHitRect.contains(point) {
            isResizing = true
            resizeStartPoint = NSEvent.mouseLocation
            resizeStartDiameter = manager?.diameter ?? 150
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isResizing else { return }
        let current = NSEvent.mouseLocation
        let delta = current.x - resizeStartPoint.x
        manager?.updateSize(resizeStartDiameter + delta)
    }

    override func mouseUp(with event: NSEvent) { isResizing = false }

    // MARK: - Context Menu

    override func rightMouseDown(with event: NSEvent) {
        guard let manager = manager else { return }
        let menu = NSMenu()

        // Size submenu
        let sizeMenu = NSMenu()
        for (label, size) in [("Small", CGFloat(100)), ("Medium", CGFloat(150)), ("Large", CGFloat(200))] {
            let item = NSMenuItem(title: label, action: #selector(changeSize(_:)), keyEquivalent: "")
            item.target = self; item.tag = Int(size)
            item.state = (abs(manager.diameter - size) < 5) ? .on : .off
            sizeMenu.addItem(item)
        }
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        // Shape submenu
        let shapeMenu = NSMenu()
        let circleItem = NSMenuItem(title: "Circle", action: #selector(setCircle), keyEquivalent: "")
        circleItem.target = self; circleItem.state = manager.shape == .circle ? .on : .off
        shapeMenu.addItem(circleItem)
        let roundedItem = NSMenuItem(title: "Rounded Rectangle", action: #selector(setRoundedRect), keyEquivalent: "")
        roundedItem.target = self; roundedItem.state = manager.shape == .roundedRect ? .on : .off
        shapeMenu.addItem(roundedItem)
        let shapeItem = NSMenuItem(title: "Shape", action: nil, keyEquivalent: "")
        shapeItem.submenu = shapeMenu
        menu.addItem(shapeItem)

        // Snap to corner submenu
        let snapMenu = NSMenu()
        for corner in WebcamOverlayManager.CornerPosition.allCases {
            let item = NSMenuItem(title: corner.label, action: #selector(snapToCorner(_:)), keyEquivalent: "")
            item.target = self; item.tag = corner.rawValue
            snapMenu.addItem(item)
        }
        let snapItem = NSMenuItem(title: "Snap to Corner", action: nil, keyEquivalent: "")
        snapItem.submenu = snapMenu
        menu.addItem(snapItem)

        // Opacity submenu
        let opacityMenu = NSMenu()
        for (label, value) in [("25%", 0.25), ("50%", 0.5), ("75%", 0.75), ("100%", 1.0)] {
            let item = NSMenuItem(title: label, action: #selector(changeOpacity(_:)), keyEquivalent: "")
            item.target = self; item.tag = Int(value * 100)
            item.state = (abs(manager.opacity - value) < 0.05) ? .on : .off
            opacityMenu.addItem(item)
        }
        let opacityItem = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
        opacityItem.submenu = opacityMenu
        menu.addItem(opacityItem)

        // Temporarily raise window above toolbars so menu renders on top
        let savedLevel = window?.level ?? .floating
        window?.level = .screenSaver
        let point = convert(event.locationInWindow, from: nil)
        menu.popUp(positioning: nil, at: point, in: self)
        window?.level = savedLevel
    }

    @objc private func changeSize(_ sender: NSMenuItem) { manager?.updateSize(CGFloat(sender.tag)) }
    @objc private func setCircle() { manager?.updateShape(.circle) }
    @objc private func setRoundedRect() { manager?.updateShape(.roundedRect) }
    @objc private func changeOpacity(_ sender: NSMenuItem) { manager?.updateOpacity(Double(sender.tag) / 100.0) }

    @objc private func snapToCorner(_ sender: NSMenuItem) {
        guard let corner = WebcamOverlayManager.CornerPosition(rawValue: sender.tag) else { return }
        manager?.snapToCorner(corner)
    }
}
