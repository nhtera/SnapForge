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
/// In window mode: detects windows under cursor, highlights them with blue border + camera icon.
/// In area mode: crosshair + drag-to-select area.
class CaptureOverlayNSView: NSView {
    var mode: CaptureMode = .area

    // Selection state (area mode)
    var selectionStart: CGPoint?
    var selectionRect: CGRect?
    var currentMousePosition: CGPoint = .zero
    var isDragging = false

    // Window mode state
    var detectedWindowRect: CGRect?  // In view coordinates (bottom-up)
    var detectedWindowTitle: String?
    var backgroundImage: NSImage?  // Frosted/blurred freeze-frame for window mode

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

        if mode == .window {
            drawWindowMode(context: context)
        } else {
            drawAreaMode(context: context)
        }
    }

    // MARK: - Window Mode Drawing

    private func drawWindowMode(context: CGContext) {
        // Very subtle dim on entire screen (barely visible, just to show overlay is active)
        context.setFillColor(NSColor.black.withAlphaComponent(0.08).cgColor)
        context.fill(bounds)

        if let windowRect = detectedWindowRect {
            // Tint the detected window with a light overlay
            context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.12).cgColor)
            let windowPath = CGPath(roundedRect: windowRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
            context.addPath(windowPath)
            context.fillPath()

            // Draw highlighted border around detected window
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(3)
            let borderRect = windowRect.insetBy(dx: -1.5, dy: -1.5)
            let borderPath = CGPath(roundedRect: borderRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
            context.addPath(borderPath)
            context.strokePath()

            // Draw subtle glow effect
            context.saveGState()
            context.setShadow(offset: .zero, blur: 12, color: NSColor.systemBlue.withAlphaComponent(0.4).cgColor)
            context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.5).cgColor)
            context.setLineWidth(2)
            context.addPath(borderPath)
            context.strokePath()
            context.restoreGState()

            // Draw centered camera icon
            drawCameraIcon(context: context, in: windowRect)

            // Draw window title pill below the window
            if let title = detectedWindowTitle, !title.isEmpty {
                drawWindowTitlePill(context: context, title: title, windowRect: windowRect)
            }
        }

        // Instruction text at bottom center
        drawInstructionText(context: context, text: "Click a window to capture  •  ESC to cancel")
    }

    /// Draw camera icon centered in the window rect — dark circle + white camera SF Symbol
    private func drawCameraIcon(context: CGContext, in rect: CGRect) {
        let iconSize: CGFloat = 48
        let centerX = rect.midX
        let centerY = rect.midY

        // Background circle
        let circleRect = CGRect(
            x: centerX - iconSize / 2 - 8,
            y: centerY - iconSize / 2 - 8,
            width: iconSize + 16,
            height: iconSize + 16
        )
        context.saveGState()
        context.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        context.fillEllipse(in: circleRect)

        // Circle border
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.4).cgColor)
        context.setLineWidth(1.5)
        context.strokeEllipse(in: circleRect)
        context.restoreGState()

        // Draw SF Symbol camera icon (tinted white)
        let config = NSImage.SymbolConfiguration(pointSize: iconSize * 0.6, weight: .medium)
        if let cameraImage = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            let imageRect = CGRect(
                x: centerX - cameraImage.size.width / 2,
                y: centerY - cameraImage.size.height / 2,
                width: cameraImage.size.width,
                height: cameraImage.size.height
            )
            // Tint the icon white — guard against copy() returning a non-NSImage type
            guard let tinted = cameraImage.copy() as? NSImage else { return }
            tinted.lockFocus()
            NSColor.white.set()
            NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 0.9)
        }
    }

    /// Draw window title pill below the detected window
    private func drawWindowTitlePill(context: CGContext, title: String, windowRect: CGRect) {
        let nsTitle = title as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let textSize = nsTitle.size(withAttributes: attrs)
        let padding: CGFloat = 10

        let pillRect = CGRect(
            x: windowRect.midX - (textSize.width + padding * 2) / 2,
            y: windowRect.minY - textSize.height - padding * 2 - 8,
            width: textSize.width + padding * 2,
            height: textSize.height + padding
        )

        let adjustedPill = pillRect.minY < 4
            ? CGRect(x: pillRect.origin.x, y: windowRect.maxY + 8, width: pillRect.width, height: pillRect.height)
            : pillRect

        context.setFillColor(NSColor.black.withAlphaComponent(0.7).cgColor)
        let path = CGPath(roundedRect: adjustedPill, cornerWidth: 6, cornerHeight: 6, transform: nil)
        context.addPath(path)
        context.fillPath()

        let textOrigin = CGPoint(
            x: adjustedPill.origin.x + padding,
            y: adjustedPill.origin.y + padding / 2
        )
        nsTitle.draw(at: textOrigin, withAttributes: attrs)
    }

    /// Draw instruction text at bottom center
    private func drawInstructionText(context: CGContext, text: String) {
        let nsText = text as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.8),
        ]
        let textSize = nsText.size(withAttributes: attrs)
        let padding: CGFloat = 12

        let pillRect = CGRect(
            x: bounds.midX - (textSize.width + padding * 2) / 2,
            y: 40,
            width: textSize.width + padding * 2,
            height: textSize.height + padding
        )

        context.setFillColor(NSColor.black.withAlphaComponent(0.6).cgColor)
        let path = CGPath(roundedRect: pillRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        context.addPath(path)
        context.fillPath()

        let textOrigin = CGPoint(
            x: pillRect.origin.x + padding,
            y: pillRect.origin.y + padding / 2
        )
        nsText.draw(at: textOrigin, withAttributes: attrs)
    }

    // MARK: - Window Detection

    /// Detect the window under the current mouse position using CGWindowListCopyWindowInfo
    private func detectWindowUnderCursor() {
        guard mode == .window else { return }
        guard let screen = window?.screen ?? NSScreen.main else { return }

        let screenHeight = screen.frame.height
        // Convert view coordinates (bottom-up) to CG coordinates (top-down)
        let cgMousePoint = CGPoint(x: currentMousePosition.x, y: screenHeight - currentMousePosition.y)

        guard let windowInfoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let excludedOwners: Set<String> = ["Window Server", "Dock", "SystemUIServer"]

        var foundRect: CGRect?
        var foundTitle: String?

        for info in windowInfoList {
            if let ownerPID = info[kCGWindowOwnerPID as String] as? Int32, ownerPID == ownPID { continue }
            if let ownerName = info[kCGWindowOwnerName as String] as? String, excludedOwners.contains(ownerName) { continue }

            // Parse window bounds using CGRect(dictionaryRepresentation:) — bridge via NSDictionary to avoid unsafe force cast
            guard let boundsAny = info[kCGWindowBounds as String],
                  let boundsNS = boundsAny as? NSDictionary,
                  let cgWindowRect = CGRect(dictionaryRepresentation: boundsNS as CFDictionary) else { continue }

            guard cgWindowRect.width > 50 && cgWindowRect.height > 50 else { continue }

            if cgWindowRect.contains(cgMousePoint) {
                // Convert CG coordinates (top-down) to view coordinates (bottom-up)
                foundRect = CGRect(
                    x: cgWindowRect.origin.x,
                    y: screenHeight - cgWindowRect.origin.y - cgWindowRect.height,
                    width: cgWindowRect.width,
                    height: cgWindowRect.height
                )
                foundTitle = (info[kCGWindowName as String] as? String)
                    ?? (info[kCGWindowOwnerName as String] as? String)
                break
            }

        }

        let changed = foundRect != detectedWindowRect
        detectedWindowRect = foundRect
        detectedWindowTitle = foundTitle

        if changed {
            needsDisplay = true
        }
    }

    // MARK: - Area Mode Drawing

    private func drawAreaMode(context: CGContext) {
        if let selection = selectionRect {
            context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
            context.fill(bounds)

            context.setBlendMode(.clear)
            context.fill(selection)
            context.setBlendMode(.normal)

            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(1.5)
            context.stroke(selection)

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

            if showDimensions {
                drawDimensionLabel(context: context, rect: selection)
            }
        } else if !isDragging {
            context.setFillColor(NSColor.black.withAlphaComponent(0.15).cgColor)
            context.fill(bounds)
        }

        if showCrosshair && !isDragging {
            drawCrosshair(context: context)
        }
    }

    private func drawCrosshair(context: CGContext) {
        let pos = currentMousePosition
        
        context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.7).cgColor)
        context.setLineWidth(0.5)
        context.setLineDash(phase: 0, lengths: [4, 4])

        context.move(to: CGPoint(x: pos.x, y: 0))
        context.addLine(to: CGPoint(x: pos.x, y: bounds.height))
        context.strokePath()

        context.move(to: CGPoint(x: 0, y: pos.y))
        context.addLine(to: CGPoint(x: bounds.width, y: pos.y))
        context.strokePath()

        context.setLineDash(phase: 0, lengths: [])

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

        let pillRect = CGRect(
            x: rect.midX - (textSize.width + padding * 2) / 2,
            y: rect.minY - textSize.height - padding * 2 - 8,
            width: textSize.width + padding * 2,
            height: textSize.height + padding
        )

        let adjustedPill = pillRect.minY < 4
            ? CGRect(x: pillRect.origin.x, y: rect.maxY + 8, width: pillRect.width, height: pillRect.height)
            : pillRect

        context.setFillColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        let path = CGPath(roundedRect: adjustedPill, cornerWidth: 4, cornerHeight: 4, transform: nil)
        context.addPath(path)
        context.fillPath()

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

        guard let window = self.window, let screen = window.screen else { return }
        let screenFrame = screen.frame

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

        if mode == .window {
            detectWindowUnderCursor()
        }

        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
        }
    }

    // Fallback — AppKit sends cancelOperation: when ESC is pressed via responder chain
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        if mode == .window {
            addCursorRect(bounds, cursor: .pointingHand)
        } else {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }
}
