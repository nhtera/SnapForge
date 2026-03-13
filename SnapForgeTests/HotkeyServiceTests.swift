import XCTest
@testable import SnapForge

/// Tests for HotkeyService — registration and key matching
final class HotkeyServiceTests: XCTestCase {

    func testHotkeyDefaults_haveCorrectKeyCodes() {
        // Carbon key codes from HIToolbox
        let area = HotkeyService.Hotkey.captureArea
        XCTAssertEqual(area.keyCode, 0x15) // kVK_ANSI_4 = 0x15 = 21
        XCTAssertEqual(area.id, "captureArea")

        let fullscreen = HotkeyService.Hotkey.captureFullscreen
        XCTAssertEqual(fullscreen.keyCode, 0x14) // kVK_ANSI_3 = 0x14 = 20
        XCTAssertEqual(fullscreen.id, "captureFullscreen")

        let window = HotkeyService.Hotkey.captureWindow
        XCTAssertEqual(window.keyCode, 0x0D) // kVK_ANSI_W = 0x0D = 13
        XCTAssertEqual(window.id, "captureWindow")
    }

    func testHotkeyModifiers_containCommandShift() {
        let area = HotkeyService.Hotkey.captureArea
        XCTAssertTrue(area.modifiers.contains(.maskCommand))
        XCTAssertTrue(area.modifiers.contains(.maskShift))
    }

    func testNSModifiers_correctlyConverted() {
        let area = HotkeyService.Hotkey.captureArea
        let nsFlags = area.nsModifiers
        XCTAssertTrue(nsFlags.contains(.command))
        XCTAssertTrue(nsFlags.contains(.shift))
        XCTAssertFalse(nsFlags.contains(.option))
        XCTAssertFalse(nsFlags.contains(.control))
    }

    func testRegisterHotkey_storesAction() {
        let service = HotkeyService()

        service.register(hotkey: .captureArea) { @Sendable in
            // no-op for test
        }

        // Verify registration count
        XCTAssertEqual(service.registeredHotkeys.count, 5, "Should have 5 default hotkeys")
    }

    func testStartListening_setsIsListening() {
        let service = HotkeyService()
        service.startListening()
        XCTAssertTrue(service.isListening)
        service.stopListening()
        XCTAssertFalse(service.isListening)
    }

    func testStartListening_idempotent() {
        let service = HotkeyService()
        service.startListening()
        service.startListening() // Should not crash or create duplicate monitors
        XCTAssertTrue(service.isListening)
        service.stopListening()
    }

    func testHotkeyCodable() throws {
        let hotkey = HotkeyService.Hotkey.captureArea
        let data = try JSONEncoder().encode(hotkey)
        let decoded = try JSONDecoder().decode(HotkeyService.Hotkey.self, from: data)
        XCTAssertEqual(decoded.id, hotkey.id)
        XCTAssertEqual(decoded.keyCode, hotkey.keyCode)
        XCTAssertEqual(decoded.modifiersRawValue, hotkey.modifiersRawValue)
    }
}
