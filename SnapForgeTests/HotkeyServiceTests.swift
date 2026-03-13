import Testing
import Foundation
@testable import SnapForge

/// Tests for HotkeyService — registration and key matching
@MainActor
struct HotkeyServiceTests {

    @Test func hotkeyDefaultsHaveCorrectKeyCodes() {
        // Carbon key codes from HIToolbox
        let area = HotkeyService.Hotkey.captureArea
        #expect(area.keyCode == 0x15) // kVK_ANSI_4 = 0x15 = 21
        #expect(area.id == "captureArea")

        let fullscreen = HotkeyService.Hotkey.captureFullscreen
        #expect(fullscreen.keyCode == 0x14) // kVK_ANSI_3 = 0x14 = 20
        #expect(fullscreen.id == "captureFullscreen")

        let window = HotkeyService.Hotkey.captureWindow
        #expect(window.keyCode == 0x0D) // kVK_ANSI_W = 0x0D = 13
        #expect(window.id == "captureWindow")
    }

    @Test func hotkeyModifiersContainCommandShift() {
        let area = HotkeyService.Hotkey.captureArea
        #expect(area.modifiers.contains(.maskCommand))
        #expect(area.modifiers.contains(.maskShift))
    }

    @Test func nsModifiersCorrectlyConverted() {
        let area = HotkeyService.Hotkey.captureArea
        let nsFlags = area.nsModifiers
        #expect(nsFlags.contains(.command))
        #expect(nsFlags.contains(.shift))
        #expect(nsFlags.contains(.option) == false)
        #expect(nsFlags.contains(.control) == false)
    }

    @Test func registerHotkeyStoresAction() {
        let service = HotkeyService()

        service.register(hotkey: .captureArea) { @Sendable in
            // no-op for test
        }

        #expect(service.registeredHotkeys.count == 5, "Should have 5 default hotkeys")
    }

    @Test func startListeningSetsIsListening() {
        let service = HotkeyService()
        service.startListening()
        #expect(service.isListening)
        service.stopListening()
        #expect(service.isListening == false)
    }

    @Test func startListeningIsIdempotent() {
        let service = HotkeyService()
        service.startListening()
        service.startListening() // Should not crash or create duplicate monitors
        #expect(service.isListening)
        service.stopListening()
    }

    @Test func hotkeyCodableRoundTrip() throws {
        let hotkey = HotkeyService.Hotkey.captureArea
        let data = try JSONEncoder().encode(hotkey)
        let decoded = try JSONDecoder().decode(HotkeyService.Hotkey.self, from: data)
        #expect(decoded.id == hotkey.id)
        #expect(decoded.keyCode == hotkey.keyCode)
        #expect(decoded.modifiersRawValue == hotkey.modifiersRawValue)
    }
}
