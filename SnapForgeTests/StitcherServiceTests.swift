import AppKit
import Testing

@testable import SnapForge

// MARK: - Stitcher Service Tests

struct StitcherServiceTests {

  /// Create a test image with the given size and color.
  private func makeImage(width: CGFloat, height: CGFloat, color: NSColor = .red) -> NSImage {
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    color.setFill()
    NSBezierPath.fill(NSRect(x: 0, y: 0, width: width, height: height))
    image.unlockFocus()
    return image
  }

  @Test func singleImagePassthrough() {
    let image = makeImage(width: 100, height: 100)
    let result = StitcherService.shared.stitch(images: [image], config: StitchConfiguration())
    #expect(result != nil)
    #expect(result?.size.width == 100)
    #expect(result?.size.height == 100)
  }

  @Test func emptyImagesReturnsNil() {
    let result = StitcherService.shared.stitch(images: [], config: StitchConfiguration())
    #expect(result == nil)
  }

  @Test func horizontalStitchCorrectDimensions() {
    let images = [
      makeImage(width: 100, height: 50),
      makeImage(width: 100, height: 50),
      makeImage(width: 100, height: 50),
    ]
    var config = StitchConfiguration()
    config.layout = .horizontal
    config.spacing = 10

    let result = StitcherService.shared.stitch(images: images, config: config)
    #expect(result != nil)
    // Total width = 100*3 + 10*2 = 320
    #expect(result!.size.width == 320)
    // Max height = 50
    #expect(result!.size.height == 50)
  }

  @Test func verticalStitchCorrectDimensions() {
    let images = [
      makeImage(width: 200, height: 100),
      makeImage(width: 200, height: 100),
    ]
    var config = StitchConfiguration()
    config.layout = .vertical
    config.spacing = 8

    let result = StitcherService.shared.stitch(images: images, config: config)
    #expect(result != nil)
    // Max width = 200
    #expect(result!.size.width == 200)
    // Total height = 100*2 + 8 = 208
    #expect(result!.size.height == 208)
  }

  @Test func gridStitchCorrectDimensions() {
    let images = [
      makeImage(width: 100, height: 100),
      makeImage(width: 100, height: 100),
      makeImage(width: 100, height: 100),
      makeImage(width: 100, height: 100),
    ]
    var config = StitchConfiguration()
    config.layout = .grid
    config.spacing = 0

    let result = StitcherService.shared.stitch(images: images, config: config)
    #expect(result != nil)
    // 4 images → 2x2 grid
    // Total width = 100*2 = 200
    // Total height = 100*2 = 200
    #expect(result!.size.width == 200)
    #expect(result!.size.height == 200)
  }

  @Test func zeroSpacingWorks() {
    let images = [
      makeImage(width: 50, height: 50),
      makeImage(width: 50, height: 50),
    ]
    var config = StitchConfiguration()
    config.layout = .horizontal
    config.spacing = 0

    let result = StitcherService.shared.stitch(images: images, config: config)
    #expect(result != nil)
    #expect(result!.size.width == 100)
  }

  @Test func mixedSizeImagesWork() {
    let images = [
      makeImage(width: 100, height: 200),
      makeImage(width: 200, height: 100),
    ]
    var config = StitchConfiguration()
    config.layout = .horizontal
    config.spacing = 10

    let result = StitcherService.shared.stitch(images: images, config: config)
    #expect(result != nil)
    // Width = 100 + 200 + 10 = 310
    #expect(result!.size.width == 310)
    // Height = max(200, 100) = 200
    #expect(result!.size.height == 200)
  }

  @Test func allLayoutCasesExist() {
    #expect(StitchLayout.allCases.count == 3)
    for layout in StitchLayout.allCases {
      #expect(!layout.displayName.isEmpty)
      #expect(!layout.icon.isEmpty)
    }
  }

  @Test func allAlignmentCasesExist() {
    #expect(StitchAlignment.allCases.count == 3)
    for alignment in StitchAlignment.allCases {
      #expect(!alignment.displayName.isEmpty)
    }
  }
}

// MARK: - Screen Diff Mode Tests

struct ScreenDiffTests {

  @Test func allDiffModesExist() {
    #expect(DiffMode.allCases.count == 3)
    for mode in DiffMode.allCases {
      #expect(!mode.displayName.isEmpty)
      #expect(!mode.icon.isEmpty)
    }
  }
}
