import AppKit

/// NSView that draws vignette overlay, selection border, resize handles,
/// and handles drag/resize interaction for the recording region.
@MainActor
final class RecordingRegionOverlayView: NSView {
    private let state: RecordingRegionState
    private var dragStartPoint: CGPoint = .zero
    private var dragStartRect: CGRect = .zero

    init(state: RecordingRegionState) {
        self.state = state
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Only accept mouse events inside the selection rect + handle padding.
    /// Clicks outside pass through to apps below.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hitArea = state.rect.insetBy(dx: -20, dy: -20) // Expand for handle hit zones
        return hitArea.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        ))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let r = state.rect

        // Vignette: semi-transparent overlay outside selection (lighter like CleanShot X)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.fill(bounds)
        ctx.clear(r)

        // Thin solid border around selection
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.6).cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(r.insetBy(dx: -0.75, dy: -0.75))

        // Corner bracket handles (L-shaped, like CleanShot X)
        let bracketLength: CGFloat = 16
        let bracketWidth: CGFloat = 2.5
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(bracketWidth)
        ctx.setLineCap(.round)

        // Top-left corner bracket
        ctx.move(to: CGPoint(x: r.minX, y: r.maxY - bracketLength))
        ctx.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        ctx.addLine(to: CGPoint(x: r.minX + bracketLength, y: r.maxY))
        ctx.strokePath()

        // Top-right corner bracket
        ctx.move(to: CGPoint(x: r.maxX - bracketLength, y: r.maxY))
        ctx.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        ctx.addLine(to: CGPoint(x: r.maxX, y: r.maxY - bracketLength))
        ctx.strokePath()

        // Bottom-left corner bracket
        ctx.move(to: CGPoint(x: r.minX, y: r.minY + bracketLength))
        ctx.addLine(to: CGPoint(x: r.minX, y: r.minY))
        ctx.addLine(to: CGPoint(x: r.minX + bracketLength, y: r.minY))
        ctx.strokePath()

        // Bottom-right corner bracket
        ctx.move(to: CGPoint(x: r.maxX - bracketLength, y: r.minY))
        ctx.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        ctx.addLine(to: CGPoint(x: r.maxX, y: r.minY + bracketLength))
        ctx.strokePath()

        // Edge midpoint handles (small circles)
        let dotRadius: CGFloat = 3
        ctx.setFillColor(NSColor.white.cgColor)
        let edgeMidpoints = [
            CGPoint(x: r.midX, y: r.maxY),  // top center
            CGPoint(x: r.midX, y: r.minY),  // bottom center
            CGPoint(x: r.minX, y: r.midY),  // left center
            CGPoint(x: r.maxX, y: r.midY),  // right center
        ]
        for pt in edgeMidpoints {
            ctx.fillEllipse(in: CGRect(
                x: pt.x - dotRadius, y: pt.y - dotRadius,
                width: dotRadius * 2, height: dotRadius * 2
            ))
        }

        // Dimensions label — bottom-center, inside the selection
        let w = Int(r.width)
        let h = Int(r.height)
        let label = "\(w) × \(h)" as NSString
        let font: NSFont = {
            let base = NSFont.systemFont(ofSize: 11, weight: .medium)
            if let desc = base.fontDescriptor.withDesign(.monospaced),
               let mono = NSFont(descriptor: desc, size: 11) { return mono }
            return base
        }()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let textSize = label.size(withAttributes: attrs)
        let labelX = r.midX - textSize.width / 2
        let labelY = r.minY + 10

        let pill = CGRect(x: labelX - 8, y: labelY - 3, width: textSize.width + 16, height: textSize.height + 6)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.6).cgColor)
        ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 6, cornerHeight: 6, transform: nil))
        ctx.fillPath()

        label.draw(at: NSPoint(x: labelX, y: labelY), withAttributes: attrs)
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // Double-click restarts selection
        if event.clickCount == 2 && state.rect.contains(point) {
            state.onDoubleClick?()
            return
        }

        // Hit-test handles first
        for handle in RecordingResizeHandle.allCases {
            let hr = state.handleRect(for: handle).insetBy(dx: -4, dy: -4)
            if hr.contains(point) {
                state.isResizing = true
                state.activeHandle = handle
                dragStartPoint = point
                dragStartRect = state.rect
                return
            }
        }

        // Inside rect: start drag
        if state.rect.contains(point) {
            state.isDragging = true
            dragStartPoint = point
            dragStartRect = state.rect
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let dx = point.x - dragStartPoint.x
        let dy = point.y - dragStartPoint.y
        let minSize = RecordingRegionState.minimumSize

        if state.isResizing, let handle = state.activeHandle {
            var r = dragStartRect
            switch handle {
            case .topLeft:      r.origin.x += dx; r.size.width -= dx; r.size.height += dy
            case .topRight:     r.size.width += dx; r.size.height += dy
            case .bottomLeft:   r.origin.x += dx; r.size.width -= dx; r.origin.y += dy; r.size.height -= dy
            case .bottomRight:  r.size.width += dx; r.origin.y += dy; r.size.height -= dy
            case .topCenter:    r.size.height += dy
            case .bottomCenter: r.origin.y += dy; r.size.height -= dy
            case .leftCenter:   r.origin.x += dx; r.size.width -= dx
            case .rightCenter:  r.size.width += dx
            }
            // Enforce minimum size
            if r.width < minSize { r.size.width = minSize }
            if r.height < minSize { r.size.height = minSize }

            state.rect = r
            state.onRectChanged?(r)
            needsDisplay = true
        } else if state.isDragging {
            var r = dragStartRect.offsetBy(dx: dx, dy: dy)
            // Clamp to bounds
            r.origin.x = max(bounds.minX, min(r.origin.x, bounds.maxX - r.width))
            r.origin.y = max(bounds.minY, min(r.origin.y, bounds.maxY - r.height))
            state.rect = r
            state.onRectChanged?(r)
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        state.isDragging = false
        state.isResizing = false
        state.activeHandle = nil
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // Check handles
        for handle in RecordingResizeHandle.allCases {
            let hr = state.handleRect(for: handle).insetBy(dx: -4, dy: -4)
            if hr.contains(point) {
                handle.cursor.set()
                return
            }
        }

        // Inside rect
        if state.rect.contains(point) {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            state.onCancel?()
        }
    }
}
