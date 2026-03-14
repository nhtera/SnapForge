import AppKit

/// Color format for clipboard copy
enum ColorCopyFormat: String, CaseIterable, Identifiable {
  case hex
  case rgb
  case hsl

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .hex: return "HEX"
    case .rgb: return "RGB"
    case .hsl: return "HSL"
    }
  }
}

/// Picked color result with formatted strings
struct PickedColor: Sendable {
  let red: CGFloat
  let green: CGFloat
  let blue: CGFloat
  let alpha: CGFloat

  /// HEX string (e.g. "#FF5733")
  var hexString: String {
    let r = Int(round(red * 255))
    let g = Int(round(green * 255))
    let b = Int(round(blue * 255))
    return String(format: "#%02X%02X%02X", r, g, b)
  }

  /// RGB string (e.g. "rgb(255, 87, 51)")
  var rgbString: String {
    let r = Int(round(red * 255))
    let g = Int(round(green * 255))
    let b = Int(round(blue * 255))
    return "rgb(\(r), \(g), \(b))"
  }

  /// HSL string (e.g. "hsl(11, 100%, 60%)")
  var hslString: String {
    let r = red
    let g = green
    let b = blue

    let maxC = max(r, g, b)
    let minC = min(r, g, b)
    let delta = maxC - minC

    // Lightness
    let l = (maxC + minC) / 2

    guard delta > 0 else {
      return "hsl(0, 0%, \(Int(round(l * 100)))%)"
    }

    // Saturation
    let s = l < 0.5 ? delta / (maxC + minC) : delta / (2 - maxC - minC)

    // Hue
    var h: CGFloat
    if maxC == r {
      h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
    } else if maxC == g {
      h = (b - r) / delta + 2
    } else {
      h = (r - g) / delta + 4
    }
    h *= 60
    if h < 0 { h += 360 }

    return "hsl(\(Int(round(h))), \(Int(round(s * 100)))%, \(Int(round(l * 100)))%)"
  }

  /// Formatted string for the given format
  func formatted(as format: ColorCopyFormat) -> String {
    switch format {
    case .hex: return hexString
    case .rgb: return rgbString
    case .hsl: return hslString
    }
  }

  /// NSColor representation
  var nsColor: NSColor {
    NSColor(red: red, green: green, blue: blue, alpha: alpha)
  }

  /// Create from NSColor (converts to sRGB color space)
  init?(from color: NSColor) {
    guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
    self.red = srgb.redComponent
    self.green = srgb.greenComponent
    self.blue = srgb.blueComponent
    self.alpha = srgb.alphaComponent
  }

  /// Direct init for programmatic construction
  init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1.0) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }
}

/// Global screen color picker using NSColorSampler.
/// Picks any pixel color from the screen and copies to clipboard.
@MainActor
final class ColorPickerService {
  static let shared = ColorPickerService()
  private init() {}

  /// Open the system color sampler and return the picked color.
  /// Returns nil if the user cancels.
  func pickColor() async -> PickedColor? {
    let sampler = NSColorSampler()
    let color = await sampler.sample()
    guard let color, let picked = PickedColor(from: color) else { return nil }
    return picked
  }

  /// Pick a color from screen and copy to clipboard in the configured format.
  func pickAndCopy() async {
    guard let picked = await pickColor() else { return }

    let formatString = UserDefaults.standard.string(forKey: SettingsKey.colorPickerCopyFormat) ?? "hex"
    let format = ColorCopyFormat(rawValue: formatString) ?? .hex
    let text = picked.formatted(as: format)

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)

    // Play sound feedback if enabled
    if UserDefaults.standard.bool(forKey: SettingsKey.playSounds) {
      NSSound(named: .init("Tink"))?.play()
    }

    print("🎨 Color picked: \(text)")
  }
}
