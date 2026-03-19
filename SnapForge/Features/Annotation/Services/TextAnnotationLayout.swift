import AppKit

/// Shared text layout engine ensuring consistent text positioning
/// between the SwiftUI TextField overlay and Core Graphics renderer.
/// Eliminates visual shift when committing/re-editing text annotations.
enum TextAnnotationLayout {
  static let horizontalPadding: CGFloat = 4
  static let verticalPadding: CGFloat = 4
  static let minWidth: CGFloat = 60

  /// Create consistent NSFont for text annotations
  static func font(size: CGFloat) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: .regular)
  }

  /// Shared paragraph style for consistent line breaking between overlay and renderer
  static func paragraphStyle() -> NSMutableParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byWordWrapping
    return style
  }

  /// Text rendering attributes with consistent font, color, and paragraph style
  static func attributes(fontSize: CGFloat, color: NSColor) -> [NSAttributedString.Key: Any] {
    [
      .font: font(size: fontSize),
      .foregroundColor: color,
      .paragraphStyle: paragraphStyle(),
    ]
  }

  /// Calculate bounding rect for multiline text within a max width
  static func multilineBounds(
    text: String,
    fontSize: CGFloat,
    maxWidth: CGFloat
  ) -> CGSize {
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font(size: fontSize),
      .paragraphStyle: paragraphStyle(),
    ]
    let constraintSize = CGSize(width: maxWidth, height: .greatestFiniteMagnitude)
    let boundingRect = (text as NSString).boundingRect(
      with: constraintSize,
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: attributes
    )
    return CGSize(
      width: ceil(boundingRect.width),
      height: ceil(boundingRect.height)
    )
  }

  /// Inner text rect within bounds (subtracts padding on all sides).
  /// Used by the renderer to draw text in the same region
  /// where the SwiftUI TextField displays its content.
  static func textRect(in bounds: CGRect) -> CGRect {
    bounds.insetBy(dx: horizontalPadding, dy: verticalPadding)
  }

  /// Minimum height for a given font size, including vertical padding
  static func minimumHeight(for fontSize: CGFloat) -> CGFloat {
    let f = font(size: fontSize)
    return ceil(f.ascender - f.descender + f.leading) + verticalPadding * 2
  }

  /// Calculate bounds centered vertically on a click point
  static func bounds(fontSize: CGFloat, origin: CGPoint, width: CGFloat) -> CGRect {
    let height = minimumHeight(for: fontSize)
    return CGRect(
      x: origin.x,
      y: origin.y - height / 2,
      width: width,
      height: height
    )
  }
}
