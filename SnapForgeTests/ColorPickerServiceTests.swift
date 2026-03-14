import AppKit
import SwiftUI
import Testing

@testable import SnapForge

// MARK: - Color Picker Tests

struct ColorPickerServiceTests {

  // MARK: - HEX Formatting

  @Test func hexStringFormatsPureRed() {
    let picked = PickedColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
    #expect(picked.hexString == "#FF0000")
  }

  @Test func hexStringFormatsPureGreen() {
    let picked = PickedColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)
    #expect(picked.hexString == "#00FF00")
  }

  @Test func hexStringFormatsPureBlue() {
    let picked = PickedColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0)
    #expect(picked.hexString == "#0000FF")
  }

  @Test func hexStringFormatsBlack() {
    let picked = PickedColor(red: 0, green: 0, blue: 0, alpha: 1)
    #expect(picked.hexString == "#000000")
  }

  @Test func hexStringFormatsWhite() {
    let picked = PickedColor(red: 1, green: 1, blue: 1, alpha: 1)
    #expect(picked.hexString == "#FFFFFF")
  }

  @Test func hexStringFormatsArbitraryColor() {
    let picked = PickedColor(red: 0.5, green: 0.25, blue: 0.75, alpha: 1)
    // 0.5 * 255 = 127.5 → 128, 0.25 * 255 = 63.75 → 64, 0.75 * 255 = 191.25 → 191
    #expect(picked.hexString == "#8040BF")
  }

  // MARK: - RGB Formatting

  @Test func rgbStringFormatsPureRed() {
    let picked = PickedColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
    #expect(picked.rgbString == "rgb(255, 0, 0)")
  }

  @Test func rgbStringFormatsMidGray() {
    let picked = PickedColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
    #expect(picked.rgbString == "rgb(128, 128, 128)")
  }

  // MARK: - HSL Formatting

  @Test func hslStringFormatsPureRed() {
    let picked = PickedColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
    #expect(picked.hslString == "hsl(0, 100%, 50%)")
  }

  @Test func hslStringFormatsBlack() {
    let picked = PickedColor(red: 0, green: 0, blue: 0, alpha: 1)
    #expect(picked.hslString == "hsl(0, 0%, 0%)")
  }

  @Test func hslStringFormatsWhite() {
    let picked = PickedColor(red: 1, green: 1, blue: 1, alpha: 1)
    #expect(picked.hslString == "hsl(0, 0%, 100%)")
  }

  // MARK: - Format Selection

  @Test func formattedAsHex() {
    let picked = PickedColor(red: 1, green: 0, blue: 0, alpha: 1)
    #expect(picked.formatted(as: .hex) == "#FF0000")
  }

  @Test func formattedAsRGB() {
    let picked = PickedColor(red: 1, green: 0, blue: 0, alpha: 1)
    #expect(picked.formatted(as: .rgb) == "rgb(255, 0, 0)")
  }

  @Test func formattedAsHSL() {
    let picked = PickedColor(red: 1, green: 0, blue: 0, alpha: 1)
    #expect(picked.formatted(as: .hsl) == "hsl(0, 100%, 50%)")
  }

  // MARK: - NSColor Conversion

  @Test func pickedColorFromNSColorSRGB() {
    let nsColor = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    let picked = PickedColor(from: nsColor)
    #expect(picked != nil)
    #expect(picked?.hexString == "#FF0000")
  }

  @Test func pickedColorRoundTripsToNSColor() {
    let picked = PickedColor(red: 0.5, green: 0.3, blue: 0.8, alpha: 1.0)
    let nsColor = picked.nsColor
    #expect(nsColor.redComponent > 0)
  }

  // MARK: - ColorCopyFormat

  @Test(arguments: ColorCopyFormat.allCases)
  func allFormatsHaveDisplayName(format: ColorCopyFormat) {
    #expect(!format.displayName.isEmpty)
  }

  @Test func formatIdsAreUnique() {
    let ids = ColorCopyFormat.allCases.map(\.id)
    #expect(Set(ids).count == ids.count)
  }
}

// MARK: - Hotkey Tests for Color Picker

struct ColorPickerHotkeyTests {

  @Test func colorPickerHotkeyExists() {
    let hotkey = HotkeyService.Hotkey.colorPicker
    #expect(hotkey.id == "colorPicker")
    #expect(hotkey.label.contains("Color"))
  }

  @Test func colorPickerHotkeyUsesCommandShiftC() {
    let hotkey = HotkeyService.Hotkey.colorPicker
    #expect(hotkey.modifiers.contains(.maskCommand))
    #expect(hotkey.modifiers.contains(.maskShift))
  }
}
