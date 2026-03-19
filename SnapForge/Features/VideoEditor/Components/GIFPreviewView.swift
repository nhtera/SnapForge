import AppKit
import SwiftUI

/// Displays an animated GIF using native NSImageView.
/// Uses `animates = true` for automatic frame cycling.
struct GIFPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        imageView.isEditable = false
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        if let image = NSImage(contentsOf: url) {
            imageView.image = image
        }
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        // Only reload if URL changed
        if nsView.image == nil {
            if let image = NSImage(contentsOf: url) {
                nsView.image = image
                nsView.animates = true
            }
        }
    }
}
