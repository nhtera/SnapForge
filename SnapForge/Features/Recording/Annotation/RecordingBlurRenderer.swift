import CoreGraphics

/// Renders blur/redaction fills for the recording canvas overlay.
/// Unlike image annotation blur, this doesn't sample underlying pixels — it draws
/// opaque patterns that SCStream composites over the recorded content.
enum RecordingBlurRenderer {

    /// Draw pixelated censorship pattern (checkerboard grid)
    static func drawPixelated(in ctx: CGContext, bounds: CGRect, pixelSize: CGFloat = 8) {
        let cols = Int(ceil(bounds.width / pixelSize))
        let rows = Int(ceil(bounds.height / pixelSize))

        for row in 0..<rows {
            for col in 0..<cols {
                let x = bounds.origin.x + CGFloat(col) * pixelSize
                let y = bounds.origin.y + CGFloat(row) * pixelSize
                let w = min(pixelSize, bounds.maxX - x)
                let h = min(pixelSize, bounds.maxY - y)
                let shade: CGFloat = ((row + col) % 2 == 0) ? 0.15 : 0.25
                ctx.setFillColor(CGColor(gray: shade, alpha: 0.95))
                ctx.fill(CGRect(x: x, y: y, width: w, height: h))
            }
        }

        ctx.setStrokeColor(CGColor(gray: 0.4, alpha: 0.8))
        ctx.setLineWidth(1)
        ctx.stroke(bounds)
    }

    /// Draw frosted glass overlay with subtle horizontal line texture
    static func drawGaussian(in ctx: CGContext, bounds: CGRect) {
        ctx.setFillColor(CGColor(gray: 0.3, alpha: 0.85))
        let path = CGPath(roundedRect: bounds, cornerWidth: 2, cornerHeight: 2, transform: nil)
        ctx.addPath(path)
        ctx.fillPath()

        // Subtle horizontal lines for frosted texture
        ctx.setStrokeColor(CGColor(gray: 0.5, alpha: 0.1))
        ctx.setLineWidth(0.5)
        var y = bounds.origin.y
        while y < bounds.maxY {
            ctx.move(to: CGPoint(x: bounds.origin.x, y: y))
            ctx.addLine(to: CGPoint(x: bounds.maxX, y: y))
            y += 2
        }
        ctx.strokePath()

        ctx.setStrokeColor(CGColor(gray: 0.5, alpha: 0.6))
        ctx.setLineWidth(1)
        ctx.stroke(bounds)
    }
}
