import AppKit

/// Full-screen dim overlay with a clear cutout for the capture zone.
/// Scroll capture bracket: dark overlay outside, clear inside with subtle border and corner brackets.
final class ScrollCaptureBracketWindow: NSPanel {

    private let captureRect: CGRect  // NS coordinates (bottom-left origin)

    init(captureRect: CGRect) {
        self.captureRect = captureRect

        guard let screen = NSScreen.main else {
            super.init(
                contentRect: captureRect,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            return
        }

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .statusBar + 1
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary]

        let drawingView = DimOverlayView(
            frame: screen.frame,
            captureRect: captureRect
        )
        contentView = drawingView
    }
}

// MARK: - Dim Overlay Drawing View

private final class DimOverlayView: NSView {

    private let captureRect: CGRect
    private let bracketLength: CGFloat = 20
    private let bracketThickness: CGFloat = 2.5

    init(frame: NSRect, captureRect: CGRect) {
        self.captureRect = captureRect
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Convert captureRect from screen coordinates to view-local coordinates
        let localRect = convert(captureRect, from: nil)

        // 1. Draw dim overlay over the entire screen
        context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        context.fill(bounds)

        // 2. Clear the capture zone (punch a hole)
        context.setBlendMode(.clear)
        context.fill(localRect)

        // 3. Reset blend mode for drawing on top
        context.setBlendMode(.normal)

        // 4. Draw subtle border around capture zone
        let borderRect = localRect.insetBy(dx: -1, dy: -1)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.4).cgColor)
        context.setLineWidth(1)
        context.stroke(borderRect)

        // 5. Draw corner brackets
        let accentColor = NSColor.controlAccentColor.cgColor
        context.setStrokeColor(accentColor)
        context.setLineWidth(bracketThickness)
        context.setLineCap(.round)

        let r = localRect
        let L = bracketLength

        // Top-left ⌜
        context.move(to: CGPoint(x: r.minX, y: r.maxY - L))
        context.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        context.addLine(to: CGPoint(x: r.minX + L, y: r.maxY))

        // Top-right ⌝
        context.move(to: CGPoint(x: r.maxX - L, y: r.maxY))
        context.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        context.addLine(to: CGPoint(x: r.maxX, y: r.maxY - L))

        // Bottom-left ⌞
        context.move(to: CGPoint(x: r.minX, y: r.minY + L))
        context.addLine(to: CGPoint(x: r.minX, y: r.minY))
        context.addLine(to: CGPoint(x: r.minX + L, y: r.minY))

        // Bottom-right ⌟
        context.move(to: CGPoint(x: r.maxX - L, y: r.minY))
        context.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        context.addLine(to: CGPoint(x: r.maxX, y: r.minY + L))

        context.strokePath()

        // 6. Scroll direction indicator (subtle downward arrow below capture zone)
        let arrowSize: CGFloat = 6
        let arrowX = r.midX
        let arrowY = r.minY - 8

        context.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor)
        context.move(to: CGPoint(x: arrowX - arrowSize, y: arrowY))
        context.addLine(to: CGPoint(x: arrowX + arrowSize, y: arrowY))
        context.addLine(to: CGPoint(x: arrowX, y: arrowY - arrowSize))
        context.closePath()
        context.fillPath()
    }
}
