import AppKit
import Testing

@testable import SnapForge

// MARK: - Quick Blur Service Tests

struct QuickBlurServiceTests {

  private func makeTestImage(width: Int = 400, height: Int = 300) -> NSImage {
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    NSColor.white.setFill()
    NSBezierPath.fill(NSRect(x: 0, y: 0, width: width, height: height))
    image.unlockFocus()
    return image
  }

  @MainActor
  @Test func autoBlurReturnsImageOfSameSize() async {
    let image = makeTestImage()
    let result = await QuickBlurService.shared.autoBlurSensitiveAreas(in: image)
    #expect(result.size == image.size)
  }

  @MainActor
  @Test func autoBlurReturnsValidImage() async {
    let image = makeTestImage()
    let result = await QuickBlurService.shared.autoBlurSensitiveAreas(in: image)
    #expect(result.size.width > 0)
    #expect(result.size.height > 0)
  }

  @MainActor
  @Test func autoBlurHandlesEmptyImage() async {
    let image = NSImage(size: .zero)
    let result = await QuickBlurService.shared.autoBlurSensitiveAreas(in: image)
    // Should return original if no CGImage can be created
    #expect(result.size == .zero)
  }
}

// MARK: - Quick Mockup Service Tests

struct QuickMockupServiceTests {

  private func makeTestImage(width: Int = 200, height: Int = 150) -> NSImage {
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    NSColor.blue.setFill()
    NSBezierPath.fill(NSRect(x: 0, y: 0, width: width, height: height))
    image.unlockFocus()
    return image
  }

  @MainActor
  @Test func applyMockupAddsCorrectPadding() {
    let image = makeTestImage(width: 200, height: 150)
    let config = QuickMockupService.MockupConfig(
      preset: .ocean, padding: 50, cornerRadius: 10, showShadow: false
    )
    let result = QuickMockupService.shared.renderMockup(image: image, config: config)

    // Expected: 200 + 50*2 = 300 wide, 150 + 50*2 = 250 tall
    #expect(result.size.width == 300)
    #expect(result.size.height == 250)
  }

  @MainActor
  @Test func applyMockupWithShadowProducesSameSize() {
    let image = makeTestImage()
    let config = QuickMockupService.MockupConfig(
      preset: .sunset, padding: 48, cornerRadius: 12, showShadow: true
    )
    let result = QuickMockupService.shared.renderMockup(image: image, config: config)

    let expectedWidth = image.size.width + 48 * 2
    let expectedHeight = image.size.height + 48 * 2
    #expect(result.size.width == expectedWidth)
    #expect(result.size.height == expectedHeight)
  }

  @MainActor
  @Test func defaultConfigHasReasonableValues() {
    let config = QuickMockupService.MockupConfig.default
    #expect(config.padding >= 16)
    #expect(config.cornerRadius >= 0)
    #expect(config.showShadow == true)
  }

  @MainActor
  @Test func saveAndLoadConfigRoundTrips() {
    let service = QuickMockupService.shared
    let config = QuickMockupService.MockupConfig(
      preset: .neon, padding: 64, cornerRadius: 16, showShadow: false
    )
    service.saveConfig(config)
    let loaded = service.loadConfig()

    #expect(loaded.preset == .neon)
    #expect(loaded.padding == 64)
    #expect(loaded.cornerRadius == 16)
    #expect(loaded.showShadow == false)
  }

  @MainActor
  @Test func applyLastMockupReturnsLargerImage() {
    let image = makeTestImage(width: 200, height: 100)
    let result = QuickMockupService.shared.applyLastMockup(to: image)
    #expect(result.size.width > image.size.width)
    #expect(result.size.height > image.size.height)
  }
}
