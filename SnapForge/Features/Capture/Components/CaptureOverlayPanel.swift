import AppKit
import SwiftUI

/// Full-screen transparent NSPanel for capture selection.
/// Uses NSPanel at .screenSaver level to overlay everything.
/// Handles mouse events for crosshair, area selection, and window picking.
class CaptureOverlayPanel: NSPanel {

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .screenSaver
        self.isOpaque = false
        self.hasShadow = false
        self.backgroundColor = .clear
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// NSView subclass that handles mouse events and renders the selection overlay.
class CaptureOverlayNSView: NSView {
    var mode: CaptureMode = .area

    // Selection state
    var selectionStart: CGPoint?
    var selectionRect: CGRect?
    var currentMousePosition: CGPoint = .zero
    var isDragging = false

    // Callbacks
    var onSelectionComplete: ((CGRect) -> Void)?
    var onWindowClicked: ((CGPoint) -> Void)?
    var onCancel: (() -> Void)?

    // Crosshair config
    var showCrosshair = true
    var showMagnifier = true
    var showDimensions = true

    // Tracking area for mouse moved events
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 1. Draw dim overlay (outside selection)
        if let selection = selectionRect {
            // Dim the entire screen
            context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
            context.fill(bounds)

            // Clear the selection area (bright hole)
            context.setBlendMode(.clear)
            context.fill(selection)
            context.setBlendMode(.normal)

            // Draw selection border
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(1.5)
            context.stroke(selection)

            // Draw resize handles (corner squares)
            let handleSize: CGFloat = 6
            let handles = [
                CGPoint(x: selection.minX, y: selection.minY),
                CGPoint(x: selection.maxX, y: selection.minY),
                CGPoint(x: selection.minX, y: selection.maxY),
                CGPoint(x: selection.maxX, y: selection.maxY),
                CGPoint(x: selection.midX, y: selection.minY),
                CGPoint(x: selection.midX, y: selection.maxY),
                CGPoint(x: selection.minX, y: selection.midY),
                CGPoint(x: selection.maxX, y: selection.midY),
            ]
            context.setFillColor(NSColor.white.cgColor)
            for handle in handles {
                let handleRect = CGRect(
                    x: handle.x - handleSize / 2,
                    y: handle.y - handleSize / 2,
                    width: handleSize,
                    height: handleSize
                )
                context.fill(handleRect)
                context.setStrokeColor(NSColor.systemBlue.cgColor)
                context.setLineWidth(1)
                context.stroke(handleRect)
            }

            // Draw dimension label
            if showDimensions {
                drawDimensionLabel(context: context, rect: selection)
            }
        } else if !isDragging {
            // No selection yet — light dim with crosshair
            context.setFillColor(NSColor.black.withAlphaComponent(0.15).cgColor)
            context.fill(bounds)
        }

        // 2. Draw crosshair (when not dragging)
        if showCrosshair && !isDragging {
            drawCrosshair(context: context)
        }
    }

    private func drawCrosshair(context: CGContext) {
        let pos = currentMousePosition
        
        context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.7).cgColor)
        context.setLineWidth(0.5)
        context.setLineDash(phase: 0, lengths: [4, 4])

        // Vertical line
        context.move(to: CGPoint(x: pos.x, y: 0))
        context.addLine(to: CGPoint(x: pos.x, y: bounds.height))
        context.strokePath()

        // Horizontal line
        context.move(to: CGPoint(x: 0, y: pos.y))
        context.addLine(to: CGPoint(x: bounds.width, y: pos.y))
        context.strokePath()

        context.setLineDash(phase: 0, lengths: [])

        // Coordinate label near cursor
        let coordText = "\(Int(pos.x)), \(Int(bounds.height - pos.y))" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.65)
        ]
        let textSize = coordText.size(withAttributes: attrs)
        let textPoint = CGPoint(
            x: min(pos.x + 14, bounds.width - textSize.width - 8),
            y: min(pos.y + 14, bounds.height - textSize.height - 8)
        )
        coordText.draw(at: textPoint, withAttributes: attrs)
    }

    private func drawDimensionLabel(context: CGContext, rect: CGRect) {
        let scaleFactor = window?.backingScaleFactor ?? 2.0
        let pixelW = Int(rect.width * scaleFactor)
        let pixelH = Int(rect.height * scaleFactor)
        let dimText = "\(pixelW) × \(pixelH)" as NSString

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let textSize = dimText.size(withAttributes: attrs)
        let padding: CGFloat = 8

        // Background pill
        let pillRect = CGRect(
            x: rect.midX - (textSize.width + padding * 2) / 2,
            y: rect.minY - textSize.height - padding * 2 - 8,
            width: textSize.width + padding * 2,
            height: textSize.height + padding
        )

        // Ensure pill is within screen bounds
        let adjustedPill = pillRect.minY < 4
            ? CGRect(x: pillRect.origin.x, y: rect.maxY + 8, width: pillRect.width, height: pillRect.height)
            : pillRect

        context.setFillColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        let path = CGPath(roundedRect: adjustedPill, cornerWidth: 4, cornerHeight: 4, transform: nil)
        context.addPath(path)
        context.fillPath()

        // Text
        let textOrigin = CGPoint(
            x: adjustedPill.origin.x + padding,
            y: adjustedPill.origin.y + padding / 2
        )
        dimText.draw(at: textOrigin, withAttributes: attrs)
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if mode == .window {
            onWindowClicked?(point)
            return
        }

        selectionStart = point
        isDragging = true
        selectionRect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let start = selectionStart else { return }
        let current = convert(event.locationInWindow, from: nil)

        selectionRect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        currentMousePosition = current
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false

        guard let rect = selectionRect, rect.width > 3, rect.height > 3 else {
            selectionRect = nil
            needsDisplay = true
            return
        }

        // Convert from view coordinates to screen coordinates
        guard let window = self.window, let screen = window.screen else { return }
        let screenFrame = screen.frame

        // NSView coordinates are flipped vs screen coordinates
        let screenRect = CGRect(
            x: rect.origin.x + screenFrame.origin.x,
            y: screenFrame.height - rect.origin.y - rect.height + screenFrame.origin.y,
            width: rect.width,
            height: rect.height
        )

        onSelectionComplete?(screenRect)
    }

    override func mouseMoved(with event: NSEvent) {
        currentMousePosition = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
        }
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }
}
