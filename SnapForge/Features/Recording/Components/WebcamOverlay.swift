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

    enum OverlayShape {
        case circle, roundedRect
    }

    // MARK: - Show/Hide

    func show() {
        guard panel == nil else { return }

        let session = AVCaptureSession()
        session.sessionPreset = .medium

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            print("⚠️ No front camera available")
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill

        let size = diameter
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let panelFrame = NSRect(
            x: screenFrame.maxX - size - 20,
            y: screenFrame.minY + 20,
            width: size,
            height: size
        )

        let overlayPanel = NSPanel(
            contentRect: panelFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        overlayPanel.level = .floating
        overlayPanel.isOpaque = false
        overlayPanel.backgroundColor = .clear
        overlayPanel.hasShadow = true
        overlayPanel.isMovableByWindowBackground = true
        overlayPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let contentView = WebcamContentView(frame: panelFrame)
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = size / 2
        contentView.layer?.masksToBounds = true
        contentView.layer?.borderColor = NSColor.white.withAlphaComponent(0.6).cgColor
        contentView.layer?.borderWidth = 3

        preview.frame = contentView.bounds
        preview.cornerRadius = size / 2
        contentView.layer?.addSublayer(preview)

        overlayPanel.contentView = contentView
        overlayPanel.alphaValue = CGFloat(opacity)
        overlayPanel.orderFrontRegardless()

        session.startRunning()

        self.panel = overlayPanel
        self.captureSession = session
        self.previewLayer = preview
        self.isVisible = true

        print("📷 Webcam overlay shown")
    }

    func hide() {
        captureSession?.stopRunning()
        captureSession = nil
        previewLayer = nil
        panel?.orderOut(nil)
        panel = nil
        isVisible = false
        print("📷 Webcam overlay hidden")
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func updateOpacity(_ value: Double) {
        opacity = value
        panel?.alphaValue = CGFloat(value)
    }

    func updateSize(_ newDiameter: CGFloat) {
        diameter = newDiameter
        guard let panel = panel, let contentView = panel.contentView else { return }

        var frame = panel.frame
        frame.size = NSSize(width: newDiameter, height: newDiameter)
        panel.setFrame(frame, display: true)

        contentView.layer?.cornerRadius = newDiameter / 2
        previewLayer?.frame = contentView.bounds
        previewLayer?.cornerRadius = newDiameter / 2
    }
}

// MARK: - Custom NSView (draggable)

private class WebcamContentView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}
