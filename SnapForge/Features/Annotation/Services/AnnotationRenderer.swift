import AppKit
import CoreGraphics
import SwiftUI

/// Renders annotations to a CGContext
struct AnnotationRenderer {
  let context: CGContext
  var editingTextId: UUID?
  var sourceImage: NSImage?
  var blurCacheManager: BlurCacheManager?

  init(
    context: CGContext,
    editingTextId: UUID? = nil,
    sourceImage: NSImage? = nil,
    blurCacheManager: BlurCacheManager? = nil
  ) {
    self.context = context
    self.editingTextId = editingTextId
    self.sourceImage = sourceImage
    self.blurCacheManager = blurCacheManager
  }

  func draw(_ annotation: AnnotationItem) {
    // Skip rendering text that is being edited (overlay handles display)
    if case .text = annotation.type, annotation.id == editingTextId {
      return
    }

    let strokeColor = NSColor(annotation.properties.strokeColor).cgColor
    let fillColor = NSColor(annotation.properties.fillColor).cgColor

    context.setStrokeColor(strokeColor)
    context.setFillColor(fillColor)
    context.setLineWidth(annotation.properties.strokeWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    switch annotation.type {
    case .rectangle:
      context.stroke(annotation.bounds)

    case .filledRectangle:
      context.fill(annotation.bounds)
      context.stroke(annotation.bounds)

    case .oval:
      context.strokeEllipse(in: annotation.bounds)

    case .arrow(let start, let end):
      drawArrow(from: start, to: end)

    case .line(let start, let end):
      context.move(to: start)
      context.addLine(to: end)
      context.strokePath()

    case .path(let points), .highlight(let points):
      drawPath(points: points, isHighlight: annotation.type.isHighlight)

    case .counter(let value):
      drawCounter(
        value: value, at: annotation.bounds.origin, color: annotation.properties.strokeColor)

    case .blur(let blurType):
      let ps =
        annotation.properties.pixelSize > 0
        ? annotation.properties.pixelSize
        : BlurEffectRenderer.defaultPixelSize
      drawBlur(
        bounds: annotation.bounds, annotationId: annotation.id, blurType: blurType, pixelSize: ps)

    case .text(let content):
      drawText(content, in: annotation.bounds, properties: annotation.properties)

    case .sticker(let sticker):
      drawSticker(sticker, in: annotation.bounds, color: annotation.properties.strokeColor)

    case .ruler(let start, let end):
      drawRuler(from: start, to: end)
    }
  }

  func drawCurrentStroke(
    tool: AnnotationToolType,
    start: CGPoint,
    currentPath: [CGPoint],
    strokeColor: Color,
    strokeWidth: CGFloat
  ) {
    context.setStrokeColor(NSColor(strokeColor).cgColor)
    context.setLineWidth(strokeWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    switch tool {
    case .pencil, .highlighter:
      if tool == .highlighter {
        context.setAlpha(0.4)
        context.setLineWidth(strokeWidth * 3)
      }
      guard currentPath.count > 1 else { return }
      context.move(to: currentPath[0])
      for point in currentPath.dropFirst() {
        context.addLine(to: point)
      }
      context.strokePath()
      context.setAlpha(1.0)

    case .rectangle:
      let currentPoint = currentPath.last ?? start
      let rect = makeRect(from: start, to: currentPoint)
      context.stroke(rect)

    case .filledRectangle:
      let currentPoint = currentPath.last ?? start
      let rect = makeRect(from: start, to: currentPoint)
      context.setFillColor(NSColor(strokeColor).withAlphaComponent(1).cgColor)
      context.fill(rect)
      context.setFillColor(NSColor.clear.cgColor)
      context.stroke(rect)

    case .oval:
      let currentPoint = currentPath.last ?? start
      let rect = makeRect(from: start, to: currentPoint)
      context.strokeEllipse(in: rect)

    case .line:
      let currentPoint = currentPath.last ?? start
      context.move(to: start)
      context.addLine(to: currentPoint)
      context.strokePath()

    case .arrow:
      let currentPoint = currentPath.last ?? start
      drawArrow(from: start, to: currentPoint)

    case .ruler:
      let currentPoint = currentPath.last ?? start
      drawRuler(from: start, to: currentPoint)

    default:
      break
    }
  }

  // MARK: - Private Drawing Helpers

  private func drawPath(points: [CGPoint], isHighlight: Bool) {
    guard points.count > 1 else { return }
    if isHighlight {
      context.setAlpha(0.4)
    }
    context.move(to: points[0])
    for point in points.dropFirst() {
      context.addLine(to: point)
    }
    context.strokePath()
    context.setAlpha(1.0)
  }

  private func drawArrow(from start: CGPoint, to end: CGPoint) {
    context.move(to: start)
    context.addLine(to: end)
    context.strokePath()

    let angle = atan2(end.y - start.y, end.x - start.x)
    let arrowLength: CGFloat = 15
    let arrowAngle: CGFloat = .pi / 6

    let point1 = CGPoint(
      x: end.x - arrowLength * cos(angle - arrowAngle),
      y: end.y - arrowLength * sin(angle - arrowAngle)
    )
    let point2 = CGPoint(
      x: end.x - arrowLength * cos(angle + arrowAngle),
      y: end.y - arrowLength * sin(angle + arrowAngle)
    )

    context.move(to: end)
    context.addLine(to: point1)
    context.move(to: end)
    context.addLine(to: point2)
    context.strokePath()
  }

  private func drawRuler(from start: CGPoint, to end: CGPoint) {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let length = sqrt(dx * dx + dy * dy)
    guard length > 0 else { return }

    // Main line
    context.move(to: start)
    context.addLine(to: end)
    context.strokePath()

    // Perpendicular direction for tick marks
    let perpX = -dy / length
    let perpY = dx / length
    let tickSize: CGFloat = 6

    // Start tick
    context.move(to: CGPoint(x: start.x + perpX * tickSize, y: start.y + perpY * tickSize))
    context.addLine(to: CGPoint(x: start.x - perpX * tickSize, y: start.y - perpY * tickSize))
    context.strokePath()

    // End tick
    context.move(to: CGPoint(x: end.x + perpX * tickSize, y: end.y + perpY * tickSize))
    context.addLine(to: CGPoint(x: end.x - perpX * tickSize, y: end.y - perpY * tickSize))
    context.strokePath()

    // Distance label
    let distanceText = "\(Int(round(length))) px" as NSString
    let midX = (start.x + end.x) / 2
    let midY = (start.y + end.y) / 2

    let fontSize: CGFloat = 11
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
      .foregroundColor: NSColor.white,
    ]
    let textSize = distanceText.size(withAttributes: attributes)

    // Background pill behind the text
    let pillPadding: CGFloat = 4
    let pillRect = CGRect(
      x: midX - textSize.width / 2 - pillPadding,
      y: midY - textSize.height / 2 - pillPadding + perpY * 14,
      width: textSize.width + pillPadding * 2,
      height: textSize.height + pillPadding * 2
    )

    context.saveGState()
    context.setFillColor(NSColor.black.withAlphaComponent(0.75).cgColor)
    let pillPath = CGPath(roundedRect: pillRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
    context.addPath(pillPath)
    context.fillPath()
    context.restoreGState()

    // Draw the distance text
    let textPoint = CGPoint(
      x: midX - textSize.width / 2,
      y: midY - textSize.height / 2 + perpY * 14
    )
    distanceText.draw(at: textPoint, withAttributes: attributes)
  }

  private func drawCounter(value: Int, at point: CGPoint, color: Color) {
    let size: CGFloat = 24
    let rect = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)

    context.setFillColor(NSColor(color).cgColor)
    context.fillEllipse(in: rect)

    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 12, weight: .bold),
      .foregroundColor: NSColor.white,
    ]
    let text = "\(value)" as NSString
    let textSize = text.size(withAttributes: attributes)
    let textPoint = CGPoint(
      x: point.x - textSize.width / 2,
      y: point.y - textSize.height / 2
    )
    text.draw(at: textPoint, withAttributes: attributes)
  }

  private func drawText(_ content: String, in bounds: CGRect, properties: AnnotationProperties) {
    let padding: CGFloat = 4
    let displayText = content.isEmpty ? "" : content

    // Draw background if fillColor is not clear
    if properties.fillColor != .clear {
      context.setFillColor(NSColor(properties.fillColor).cgColor)
      // bounds already includes padding, so use directly
      context.fill(bounds)
    }

    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: properties.fontSize, weight: .regular),
      .foregroundColor: NSColor(properties.strokeColor),
    ]
    let text = displayText as NSString
    // Draw text inset by padding within the padded bounds
    let textPoint = CGPoint(x: bounds.origin.x + padding, y: bounds.origin.y + padding)
    text.draw(at: textPoint, withAttributes: attributes)
  }

  private func makeRect(from start: CGPoint, to end: CGPoint) -> CGRect {
    CGRect(
      x: min(start.x, end.x),
      y: min(start.y, end.y),
      width: abs(end.x - start.x),
      height: abs(end.y - start.y)
    )
  }

  private func drawBlur(bounds: CGRect, annotationId: UUID, blurType: BlurType, pixelSize: CGFloat)
  {
    // Skip zero-size regions
    guard bounds.width > 0, bounds.height > 0 else { return }

    guard let sourceImage else {
      print(
        "⚠️ Blur fallback: sourceImage is nil for annotation \(annotationId) — content will appear lost"
      )
      BlurEffectRenderer.drawFallback(in: context, region: bounds)
      return
    }

    // Try cached version first for performance
    if let cacheManager = blurCacheManager,
      let cachedImage = cacheManager.getCachedBlur(
        for: annotationId,
        bounds: bounds,
        sourceImage: sourceImage,
        blurType: blurType,
        pixelSize: pixelSize
      )
    {
      context.draw(cachedImage, in: bounds)
      return
    }

    // Fallback to direct render
    switch blurType {
    case .pixelated:
      BlurEffectRenderer.drawPixelatedRegion(
        in: context,
        sourceImage: sourceImage,
        region: bounds,
        pixelSize: pixelSize
      )
    case .gaussian:
      BlurEffectRenderer.drawGaussianRegion(
        in: context,
        sourceImage: sourceImage,
        region: bounds
      )
    }
  }

  /// Draw blur preview during drag operation
  func drawBlurPreview(
    start: CGPoint, currentPoint: CGPoint, strokeColor: Color, blurType: BlurType
  ) {
    let rect = makeRect(from: start, to: currentPoint)
    guard rect.width > 0, rect.height > 0 else { return }

    if let sourceImage {
      switch blurType {
      case .pixelated:
        BlurEffectRenderer.drawPixelatedRegion(
          in: context,
          sourceImage: sourceImage,
          region: rect,
          pixelSize: BlurEffectRenderer.defaultPixelSize
        )
      case .gaussian:
        BlurEffectRenderer.drawGaussianRegion(
          in: context,
          sourceImage: sourceImage,
          region: rect
        )
      }
    }

    // Draw border indicator
    context.setStrokeColor(NSColor(strokeColor).cgColor)
    context.setLineWidth(2)
    context.setLineDash(phase: 0, lengths: [6, 4])
    context.stroke(rect)
    context.setLineDash(phase: 0, lengths: [])
  }

  private func drawSticker(_ sticker: StickerItem, in bounds: CGRect, color: Color) {
    let config = NSImage.SymbolConfiguration(pointSize: bounds.height * 0.8, weight: .regular)
    guard
      let symbolImage = NSImage(
        systemSymbolName: sticker.symbol,
        accessibilityDescription: sticker.name
      )?.withSymbolConfiguration(config)
    else { return }

    // Tint the symbol with the annotation color
    let tintedImage = NSImage(size: bounds.size, flipped: false) { drawRect in
      NSColor(color).set()
      symbolImage.draw(
        in: drawRect,
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0
      )
      // Apply tint via source atop compositing
      NSColor(color).set()
      drawRect.fill(using: .sourceAtop)
      return true
    }

    context.saveGState()
    if let cgImage = tintedImage.cgImage(
      forProposedRect: nil, context: nil, hints: nil
    ) {
      context.draw(cgImage, in: bounds)
    }
    context.restoreGState()
  }
}
