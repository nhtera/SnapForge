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

  /// Text rendering attributes with consistent font and color
  static func attributes(fontSize: CGFloat, color: NSColor) -> [NSAttributedString.Key: Any] {
    [
      .font: font(size: fontSize),
      .foregroundColor: color,
    ]
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
