import AppKit

/// Layout options for stitching multiple screenshots together.
enum StitchLayout: String, CaseIterable, Identifiable {
  case horizontal
  case vertical
  case grid

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .horizontal: "Horizontal"
    case .vertical: "Vertical"
    case .grid: "Grid"
    }
  }

  var icon: String {
    switch self {
    case .horizontal: "rectangle.split.3x1"
    case .vertical: "rectangle.split.1x2"
    case .grid: "rectangle.split.2x2"
    }
  }
}

/// Alignment within a stitched layout.
enum StitchAlignment: String, CaseIterable, Identifiable {
  case start
  case center
  case end

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .start: "Start"
    case .center: "Center"
    case .end: "End"
    }
  }
}

/// Configuration for stitching images.
struct StitchConfiguration {
  var layout: StitchLayout = .horizontal
  var spacing: CGFloat = 8
  var backgroundColor: NSColor = .windowBackgroundColor
  var alignment: StitchAlignment = .center
  var cornerRadius: CGFloat = 0
}

/// Service that composites multiple images into a single stitched image.
final class StitcherService: Sendable {
  static let shared = StitcherService()
  private init() {}

  /// Stitch images together using the given configuration.
  /// Returns a composite NSImage.
  func stitch(images: [NSImage], config: StitchConfiguration) -> NSImage? {
    guard !images.isEmpty else { return nil }
    if images.count == 1 { return images[0] }

    switch config.layout {
    case .horizontal:
      return stitchHorizontal(images: images, config: config)
    case .vertical:
      return stitchVertical(images: images, config: config)
    case .grid:
      return stitchGrid(images: images, config: config)
    }
  }

  // MARK: - Horizontal

  private func stitchHorizontal(images: [NSImage], config: StitchConfiguration) -> NSImage? {
    let sizes = images.map(\.size)
    let totalSpacing = config.spacing * CGFloat(images.count - 1)
    let totalWidth = sizes.reduce(CGFloat(0)) { $0 + $1.width } + totalSpacing
    let maxHeight = sizes.map(\.height).max() ?? 0

    let canvasSize = NSSize(width: totalWidth, height: maxHeight)
    return renderComposite(images: images, canvasSize: canvasSize, config: config) { index, image in
      let sizes = images.prefix(index).map(\.size)
      let x = sizes.reduce(CGFloat(0)) { $0 + $1.width } + config.spacing * CGFloat(index)
      let y: CGFloat
      switch config.alignment {
      case .start: y = 0
      case .center: y = (maxHeight - image.size.height) / 2
      case .end: y = maxHeight - image.size.height
      }
      return CGRect(x: x, y: y, width: image.size.width, height: image.size.height)
    }
  }

  // MARK: - Vertical

  private func stitchVertical(images: [NSImage], config: StitchConfiguration) -> NSImage? {
    let sizes = images.map(\.size)
    let totalSpacing = config.spacing * CGFloat(images.count - 1)
    let maxWidth = sizes.map(\.width).max() ?? 0
    let totalHeight = sizes.reduce(CGFloat(0)) { $0 + $1.height } + totalSpacing

    let canvasSize = NSSize(width: maxWidth, height: totalHeight)
    return renderComposite(images: images, canvasSize: canvasSize, config: config) { index, image in
      // Stack from top to bottom — in Cocoa coordinates (y=0 at bottom),
      // we reverse the order so the first image appears at the top.
      let belowSizes = images.suffix(from: index + 1).map(\.size)
      let y = belowSizes.reduce(CGFloat(0)) { $0 + $1.height } + config.spacing * CGFloat(images.count - 1 - index)
      let x: CGFloat
      switch config.alignment {
      case .start: x = 0
      case .center: x = (maxWidth - image.size.width) / 2
      case .end: x = maxWidth - image.size.width
      }
      return CGRect(x: x, y: y, width: image.size.width, height: image.size.height)
    }
  }

  // MARK: - Grid

  private func stitchGrid(images: [NSImage], config: StitchConfiguration) -> NSImage? {
    let count = images.count
    let cols = Int(ceil(sqrt(Double(count))))
    let rows = Int(ceil(Double(count) / Double(cols)))

    let maxWidth = images.map(\.size.width).max() ?? 0
    let maxHeight = images.map(\.size.height).max() ?? 0

    let totalWidth = maxWidth * CGFloat(cols) + config.spacing * CGFloat(cols - 1)
    let totalHeight = maxHeight * CGFloat(rows) + config.spacing * CGFloat(rows - 1)

    let canvasSize = NSSize(width: totalWidth, height: totalHeight)
    return renderComposite(images: images, canvasSize: canvasSize, config: config) { index, image in
      let col = index % cols
      let row = index / cols
      let invertedRow = rows - 1 - row  // Cocoa: y=0 at bottom

      let x = CGFloat(col) * (maxWidth + config.spacing) + (maxWidth - image.size.width) / 2
      let y = CGFloat(invertedRow) * (maxHeight + config.spacing) + (maxHeight - image.size.height) / 2
      return CGRect(x: x, y: y, width: image.size.width, height: image.size.height)
    }
  }

  // MARK: - Render

  private func renderComposite(
    images: [NSImage],
    canvasSize: NSSize,
    config: StitchConfiguration,
    rectForImage: (Int, NSImage) -> CGRect
  ) -> NSImage? {
    let result = NSImage(size: canvasSize)
    result.lockFocus()

    // Background
    config.backgroundColor.setFill()
    NSBezierPath.fill(NSRect(origin: .zero, size: canvasSize))

    // Draw each image
    for (index, image) in images.enumerated() {
      let rect = rectForImage(index, image)
      if config.cornerRadius > 0 {
        let path = NSBezierPath(roundedRect: rect, xRadius: config.cornerRadius, yRadius: config.cornerRadius)
        path.addClip()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.current?.cgContext.resetClip()
      } else {
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
      }
    }

    result.unlockFocus()
    return result
  }
}
