import AppKit

/// Simple NSView that draws a semi-transparent dim overlay with a clear cutout
/// for the recording region. Used during recording when "Dim screen" is enabled.
/// This view is click-through (set on the parent NSWindow).
final class RecordingDimOverlayNSView: NSView {
    private var cutoutRect: CGRect

    init(cutoutRect: CGRect) {
        self.cutoutRect = cutoutRect
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func updateCutoutRect(_ rect: CGRect) {
        cutoutRect = rect
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // Fill entire view with dim color
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.4).cgColor)
        ctx.fill(bounds)
        // Clear the recording area cutout
        ctx.setBlendMode(.clear)
        ctx.fill(cutoutRect)
    }
}
