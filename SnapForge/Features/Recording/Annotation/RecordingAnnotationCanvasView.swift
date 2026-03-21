import AppKit
import SwiftUI

/// NSView for drawing annotations during screen recording.
/// Handles mouse events for drawing shapes and renders via AnnotationRenderer.
@MainActor
final class RecordingAnnotationCanvasView: NSView {
    private let state: RecordingAnnotationState

    // Drawing state
    private var isDrawing = false
    private var drawStart: CGPoint = .zero
    private var currentPath: [CGPoint] = []
    private var dragOffset: CGPoint = .zero
    private var isDraggingAnnotation = false
    private lazy var textOverlay = RecordingAnnotationTextOverlay(state: state)
    /// Current mouse position for counter preview
    private var hoverPoint: CGPoint?

    init(state: RecordingAnnotationState) {
        self.state = state
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = .clear
        state.laserPointerState.canvasView = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self, userInfo: nil
        ))
    }

    func refresh() { needsDisplay = true }

    /// Dismiss active text overlay (called when switching tools)
    func dismissTextOverlay() {
        if textOverlay.isActive {
            textOverlay.commit()
        }
    }

    /// Update cursor for current tool (called from canvas window observer)
    func updateCursorForTool() {
        window?.invalidateCursorRects(for: self)
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        super.resetCursorRects()
        switch state.selectedTool {
        case .text:
            addCursorRect(bounds, cursor: .iBeam)
        case .counter:
            addCursorRect(bounds, cursor: .crosshair)
        case .selection:
            addCursorRect(bounds, cursor: .arrow)
        default:
            addCursorRect(bounds, cursor: .crosshair)
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let cgContext = NSGraphicsContext.current?.cgContext else { return }
        cgContext.clear(bounds)

        let renderer = AnnotationRenderer(context: cgContext)

        // Spotlight overlay pass FIRST — so other annotations render on top of the dark overlay
        let spotlightEntries = state.annotations.filter {
            if case .spotlight = $0.item.type { return true }
            return false
        }
        if !spotlightEntries.isEmpty {
            cgContext.saveGState()
            cgContext.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
            cgContext.fill(bounds)
            cgContext.setBlendMode(.clear)
            for entry in spotlightEntries {
                cgContext.saveGState()
                cgContext.setAlpha(entry.opacity)
                cgContext.fillEllipse(in: entry.item.bounds)
                cgContext.restoreGState()
            }
            cgContext.restoreGState()
        }

        // Draw existing annotations (non-spotlight) with opacity — rendered ON TOP of spotlight overlay
        for entry in state.annotations {
            if case .spotlight = entry.item.type { continue }
            if entry.id == textOverlay.currentEditingId { continue }

            cgContext.saveGState()
            cgContext.setAlpha(entry.opacity)

            if case .blur(let blurType) = entry.item.type {
                switch blurType {
                case .pixelated: RecordingBlurRenderer.drawPixelated(in: cgContext, bounds: entry.item.bounds)
                case .gaussian: RecordingBlurRenderer.drawGaussian(in: cgContext, bounds: entry.item.bounds)
                }
            } else if case .text(let content) = entry.item.type {
                drawTextAnnotation(in: cgContext, content: content, item: entry.item)
            } else {
                renderer.draw(entry.item)
            }
            cgContext.restoreGState()
        }

        // Laser pointer trail (ephemeral, not an annotation)
        if state.selectedTool == .laserPointer {
            state.laserPointerState.drawTrail(in: cgContext, color: NSColor(state.strokeColor))
        }

        // Draw selection highlight
        if let selectedId = state.selectedAnnotationId,
           let entry = state.annotations.first(where: { $0.id == selectedId }) {
            cgContext.setStrokeColor(NSColor.systemBlue.cgColor)
            cgContext.setLineWidth(1)
            cgContext.setLineDash(phase: 0, lengths: [4, 4])
            let selRect = entry.item.bounds.insetBy(dx: -4, dy: -4)
            cgContext.stroke(selRect)
            cgContext.setLineDash(phase: 0, lengths: [])
        }

        // Draw in-progress stroke
        if isDrawing && state.selectedTool == .blur {
            // Live blur preview during drag
            let last = currentPath.last ?? drawStart
            let previewRect = CGRect(
                x: min(drawStart.x, last.x), y: min(drawStart.y, last.y),
                width: abs(last.x - drawStart.x), height: abs(last.y - drawStart.y)
            )
            if previewRect.width > 5, previewRect.height > 5 {
                cgContext.saveGState()
                cgContext.setAlpha(0.6)
                switch state.selectedBlurType {
                case .pixelated: RecordingBlurRenderer.drawPixelated(in: cgContext, bounds: previewRect)
                case .gaussian: RecordingBlurRenderer.drawGaussian(in: cgContext, bounds: previewRect)
                }
                cgContext.restoreGState()
            }
        } else if isDrawing && state.selectedTool == .spotlight {
            // Spotlight preview: dark overlay with ellipse cutout
            let last = currentPath.last ?? drawStart
            let previewRect = CGRect(
                x: min(drawStart.x, last.x), y: min(drawStart.y, last.y),
                width: abs(last.x - drawStart.x), height: abs(last.y - drawStart.y)
            )
            if previewRect.width > 10, previewRect.height > 10 {
                cgContext.saveGState()
                cgContext.setFillColor(NSColor.black.withAlphaComponent(0.3).cgColor)
                cgContext.fill(bounds)
                cgContext.setBlendMode(.clear)
                cgContext.fillEllipse(in: previewRect)
                cgContext.restoreGState()
            }
        } else if isDrawing && state.selectedTool != .selection {
            renderer.drawCurrentStroke(
                tool: state.selectedTool,
                start: drawStart,
                currentPath: currentPath,
                strokeColor: state.strokeColor,
                strokeWidth: state.strokeWidth
            )
        }

        // Draw counter preview ghost at hover position
        if state.selectedTool == .counter, let hover = hoverPoint {
            drawCounterPreview(in: cgContext, at: hover)
        }
    }

    /// Draw text annotation matching NSTextField's internal text layout.
    /// bounds = original NSTextField frame, so we use draw(in:) for automatic vertical alignment.
    private func drawTextAnnotation(in ctx: CGContext, content: String, item: AnnotationItem) {
        let fontSize = item.properties.fontSize
        let font = NSFont.systemFont(ofSize: fontSize)
        let color = NSColor(item.properties.strokeColor)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineBreakMode = .byClipping

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle,
        ]

        // Inset to match NSTextField's internal cell padding (~2px horizontal)
        let drawRect = item.bounds.insetBy(dx: 2, dy: 0)
        let attrStr = NSAttributedString(string: content, attributes: attrs)
        attrStr.draw(in: drawRect)
    }

    /// Draw a semi-transparent counter circle preview at hover position
    private func drawCounterPreview(in ctx: CGContext, at center: CGPoint) {
        let size: CGFloat = 24
        // Match renderer: center point - size/2
        let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        ctx.saveGState()
        ctx.setAlpha(0.3)
        ctx.setFillColor(NSColor(state.strokeColor).cgColor)
        ctx.fillEllipse(in: rect)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.4).cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokeEllipse(in: rect)
        ctx.restoreGState()
    }

    // MARK: - Mouse Events

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if state.selectedTool == .laserPointer {
            state.laserPointerState.addPoint(point)
            needsDisplay = true
        } else if state.selectedTool == .counter {
            hoverPoint = point
            needsDisplay = true
        } else if hoverPoint != nil {
            hoverPoint = nil
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        if hoverPoint != nil {
            hoverPoint = nil
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // Laser pointer only tracks mouseMoved — no click action
        if state.selectedTool == .laserPointer { return }

        // Commit active text field before handling new click
        if textOverlay.isActive {
            textOverlay.commit()
        }

        if state.selectedTool == .selection {
            // Hit-test for selection
            if let entry = state.annotations.reversed().first(where: { $0.item.containsPoint(point) }) {
                state.selectedAnnotationId = entry.id
                isDraggingAnnotation = true
                dragOffset = CGPoint(x: point.x - entry.item.bounds.origin.x, y: point.y - entry.item.bounds.origin.y)
            } else {
                state.selectedAnnotationId = nil
            }
        } else if state.selectedTool == .text {
            // Click on existing text annotation → edit it; otherwise create new
            if let entry = state.annotations.reversed().first(where: { $0.item.containsPoint(point) }),
               case .text(let existingText) = entry.item.type {
                handleTextEdit(entry: entry, existingText: existingText)
            } else {
                drawStart = point
            }
        } else if state.selectedTool == .counter {
            drawStart = point
        } else {
            isDrawing = true
            drawStart = point
            currentPath = [point]
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if isDraggingAnnotation, let selectedId = state.selectedAnnotationId,
           let idx = state.annotations.firstIndex(where: { $0.id == selectedId }) {
            var item = state.annotations[idx].item
            item.bounds.origin = CGPoint(x: point.x - dragOffset.x, y: point.y - dragOffset.y)
            state.annotations[idx] = RecordingAnnotationEntry(item: item, tool: state.annotations[idx].createdByTool)
        } else if isDrawing {
            currentPath.append(point)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if isDraggingAnnotation {
            isDraggingAnnotation = false
        } else if state.selectedTool == .text {
            handleTextClick(at: point)
        } else if state.selectedTool == .counter {
            handleCounterClick(at: point)
        } else if isDrawing {
            isDrawing = false
            if var annotation = RecordingAnnotationFactory.createAnnotation(
                tool: state.selectedTool, from: drawStart, to: point,
                path: currentPath, strokeColor: state.strokeColor,
                strokeWidth: state.strokeWidth
            ) {
                // Set the selected blur type for blur annotations
                if state.selectedTool == .blur {
                    annotation.type = .blur(state.selectedBlurType)
                }
                state.appendAnnotation(annotation, tool: state.selectedTool)
            }
            currentPath.removeAll()
        }
        needsDisplay = true
    }

    // MARK: - Text & Counter

    private func handleTextClick(at point: CGPoint) {
        guard !textOverlay.isActive else { return }
        textOverlay.onCommit = { [weak self] text, fieldFrame in
            guard let self else { return }
            let fontSize = self.state.selectedFontSize
            // Store the field frame as bounds — canvas renders text matching NSTextField layout
            let props = AnnotationProperties(strokeColor: self.state.strokeColor, fontSize: fontSize)
            let item = AnnotationItem(type: .text(text), bounds: fieldFrame, properties: props)
            self.state.appendAnnotation(item, tool: .text)
        }
        textOverlay.show(at: point, in: self)
    }

    /// Click on existing text annotation while in text tool to edit it
    private func handleTextEdit(entry: RecordingAnnotationEntry, existingText: String) {
        guard !textOverlay.isActive else { return }
        let fontSize = entry.item.properties.fontSize
        let color = NSColor(entry.item.properties.strokeColor)

        textOverlay.onEditCommit = { [weak self] annotationId, newText in
            guard let self,
                  let idx = self.state.annotations.firstIndex(where: { $0.id == annotationId }) else { return }
            let fs = self.state.annotations[idx].item.properties.fontSize
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fs)]
            let textSize = (newText as NSString).size(withAttributes: attrs)
            var item = self.state.annotations[idx].item
            item.type = .text(newText)
            // Update width to fit new text, keep height
            item.bounds.size.width = max(textSize.width + 8, 40)
            self.state.annotations[idx] = RecordingAnnotationEntry(item: item, tool: .text)
            self.needsDisplay = true
        }
        // Pass bounds (= original field frame) so the edit field appears at the same position
        textOverlay.showForEditing(
            annotationId: entry.id, text: existingText,
            bounds: entry.item.bounds, fontSize: fontSize, color: color, in: self
        )
    }

    private func handleCounterClick(at point: CGPoint) {
        let value = state.nextCounterValue
        state.nextCounterValue += 1
        let size: CGFloat = 24
        // Renderer uses bounds.origin as center point for counter circles
        let bounds = CGRect(x: point.x, y: point.y, width: size, height: size)
        let props = AnnotationProperties(strokeColor: state.strokeColor)
        let item = AnnotationItem(type: .counter(value), bounds: bounds, properties: props)
        state.appendAnnotation(item, tool: .counter)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        // Cmd+Z / Cmd+Shift+Z for undo/redo
        if event.modifierFlags.contains(.command), event.keyCode == 6 {
            if event.modifierFlags.contains(.shift) {
                state.redo()
            } else {
                state.undo()
            }
            return
        }

        switch event.keyCode {
        case 51, 117: // Delete, Forward Delete
            state.deleteSelected()
        case 53: // Escape
            if textOverlay.isActive {
                textOverlay.dismiss()
            } else {
                state.selectedAnnotationId = nil
            }
            needsDisplay = true
        default:
            if let char = event.characters?.lowercased().first {
                for tool in RecordingAnnotationState.availableTools {
                    if tool.defaultShortcut == char {
                        state.selectedTool = tool
                        break
                    }
                }
            }
        }
    }
}
