import AppKit
import SwiftUI

/// Service to instantly apply background mockup to an image using last-used preset.
/// Provides one-click beautification without opening the full mockup editor.
@MainActor
final class QuickMockupService {
  static let shared = QuickMockupService()
  private init() {}

  // MARK: - UserDefaults Keys

  private enum Keys {
    static let lastPreset = "quickMockup.lastPreset"
    static let lastPadding = "quickMockup.lastPadding"
    static let lastCornerRadius = "quickMockup.lastCornerRadius"
    static let lastShowShadow = "quickMockup.lastShowShadow"
  }

  // MARK: - Configuration

  struct MockupConfig {
    var preset: GradientPreset
    var padding: CGFloat
    var cornerRadius: CGFloat
    var showShadow: Bool

    static let `default` = MockupConfig(
      preset: .ocean,
      padding: 48,
      cornerRadius: 12,
      showShadow: true
    )
  }

  /// Save the current mockup configuration for quick reuse
  func saveConfig(_ config: MockupConfig) {
    let defaults = UserDefaults.standard
    defaults.set(config.preset.rawValue, forKey: Keys.lastPreset)
    defaults.set(Double(config.padding), forKey: Keys.lastPadding)
    defaults.set(Double(config.cornerRadius), forKey: Keys.lastCornerRadius)
    defaults.set(config.showShadow, forKey: Keys.lastShowShadow)
  }

  /// Load last-used mockup configuration
  func loadConfig() -> MockupConfig {
    let defaults = UserDefaults.standard

    let presetRaw = defaults.string(forKey: Keys.lastPreset) ?? "ocean"
    let preset = GradientPreset(rawValue: presetRaw) ?? .ocean
    let padding = defaults.double(forKey: Keys.lastPadding)
    let cornerRadius = defaults.double(forKey: Keys.lastCornerRadius)
    let showShadow = defaults.object(forKey: Keys.lastShowShadow) as? Bool ?? true

    return MockupConfig(
      preset: preset,
      padding: padding > 0 ? CGFloat(padding) : 48,
      cornerRadius: cornerRadius > 0 ? CGFloat(cornerRadius) : 12,
      showShadow: showShadow
    )
  }

  // MARK: - Apply Mockup

  /// Apply last-used mockup preset to an image. Returns the composite image.
  func applyLastMockup(to image: NSImage) -> NSImage {
    let config = loadConfig()
    return renderMockup(image: image, config: config)
  }

  /// Render a mockup with the given configuration
  func renderMockup(image: NSImage, config: MockupConfig) -> NSImage {
    let imageSize = image.size
    let totalWidth = imageSize.width + config.padding * 2
    let totalHeight = imageSize.height + config.padding * 2

    let composite = NSImage(size: NSSize(width: totalWidth, height: totalHeight), flipped: false) { rect in
      // Draw gradient background
      let bgRect = NSRect(origin: .zero, size: rect.size)
      let gradient = NSGradient(
        starting: NSColor(config.preset.colors.first ?? .blue),
        ending: NSColor(config.preset.colors.last ?? .purple)
      )
      gradient?.draw(in: bgRect, angle: config.preset.angle)

      // Draw shadow
      if config.showShadow {
        let shadowRect = NSRect(
          x: config.padding, y: config.padding,
          width: imageSize.width, height: imageSize.height
        )
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 20
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.set()

        NSColor.black.withAlphaComponent(0.5).setFill()
        let shadowPath = NSBezierPath(
          roundedRect: shadowRect,
          xRadius: config.cornerRadius,
          yRadius: config.cornerRadius
        )
        shadowPath.fill()

        // Reset shadow
        NSShadow().set()
      }

      // Draw image with corner radius
      let imageRect = NSRect(
        x: config.padding, y: config.padding,
        width: imageSize.width, height: imageSize.height
      )
      let clipPath = NSBezierPath(
        roundedRect: imageRect,
        xRadius: config.cornerRadius,
        yRadius: config.cornerRadius
      )
      clipPath.addClip()
      image.draw(in: imageRect)

      return true
    }
    return composite
  }
}
