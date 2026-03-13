import SwiftUI

/// NSImage extensions for common operations.
extension NSImage {
    /// Create NSImage from CGImage with proper scaling.
    convenience init(cgImage: CGImage, size: NSSize) {
        self.init(cgImage: cgImage, size: size)
    }

    /// Get the pixel dimensions (accounting for Retina).
    var pixelSize: NSSize {
        guard let rep = representations.first else { return size }
        return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }

    /// Scale image to fit within maxSize while maintaining aspect ratio.
    func scaled(toFit maxSize: NSSize) -> NSImage {
        let ratio = min(maxSize.width / size.width, maxSize.height / size.height)
        if ratio >= 1 { return self }

        let newSize = NSSize(width: size.width * ratio, height: size.height * ratio)
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        draw(in: NSRect(origin: .zero, size: newSize),
             from: NSRect(origin: .zero, size: size),
             operation: .copy,
             fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
}
