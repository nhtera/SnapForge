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

    init(state: RecordingAnnotationState) {
        self.state = state
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        ))
    }

    func refresh() { needsDisplay = true }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let cgContext = NSGraphicsContext.current?.cgContext else { return }
        cgContext.clear(bounds)

        let renderer = AnnotationRenderer(context: cgContext)

        // Draw existing annotations with opacity
        for entry in state.annotations {
            cgContext.saveGState()
            cgContext.setAlpha(entry.opacity)
            renderer.draw(entry.item)
            cgContext.restoreGState()
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
        if isDrawing && state.selectedTool != .selection {
            renderer.drawCurrentStroke(
                tool: state.selectedTool,
                start: drawStart,
                currentPath: currentPath,
                strokeColor: state.strokeColor,
                strokeWidth: state.strokeWidth
            )
        }
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if state.selectedTool == .selection {
            // Hit-test for selection
            if let entry = state.annotations.reversed().first(where: { $0.item.containsPoint(point) }) {
                state.selectedAnnotationId = entry.id
                isDraggingAnnotation = true
                dragOffset = CGPoint(x: point.x - entry.item.bounds.origin.x, y: point.y - entry.item.bounds.origin.y)
            } else {
                state.selectedAnnotationId = nil
            }
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
        } else if isDrawing {
            isDrawing = false
            if let annotation = RecordingAnnotationFactory.createAnnotation(
                tool: state.selectedTool, from: drawStart, to: point,
                path: currentPath, strokeColor: state.strokeColor,
                strokeWidth: state.strokeWidth
            ) {
                state.appendAnnotation(annotation, tool: state.selectedTool)
            }
            currentPath.removeAll()
        }
        needsDisplay = true
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
            state.selectedAnnotationId = nil
            needsDisplay = true
        default:
            // Tool shortcuts — when shortcut mode active or canvas is focused
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
