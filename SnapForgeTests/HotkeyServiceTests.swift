import Testing
import Foundation
@testable import SnapForge

/// Tests for HotkeyService — registration, customization, persistence, and conflict detection
@MainActor
struct HotkeyServiceTests {

    // MARK: - Default Hotkeys

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

        #expect(service.registeredHotkeys.count == HotkeyService.defaultHotkeys.count,
                "Should have all default hotkeys")
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

    // MARK: - Update Hotkey

    @Test func updateHotkeyChangesKeyCode() {
        let service = HotkeyService()

        // Update captureArea from ⌘⇧4 to ⌘⇧A (keyCode 0x00 = A)
        service.updateHotkey(id: "captureArea", keyCode: 0x00, modifiers: [.maskCommand, .maskShift])

        let updated = service.registeredHotkeys.first(where: { $0.id == "captureArea" })
        #expect(updated != nil)
        #expect(updated?.keyCode == 0x00)
        #expect(updated?.modifiers.contains(.maskCommand) == true)
        #expect(updated?.modifiers.contains(.maskShift) == true)
    }

    @Test func updateHotkeyChangesModifiers() {
        let service = HotkeyService()

        // Change captureArea to ⌃⌥4 instead of ⌘⇧4
        service.updateHotkey(id: "captureArea", keyCode: 0x15, modifiers: [.maskControl, .maskAlternate])

        let updated = service.registeredHotkeys.first(where: { $0.id == "captureArea" })
        #expect(updated != nil)
        #expect(updated?.modifiers.contains(.maskControl) == true)
        #expect(updated?.modifiers.contains(.maskAlternate) == true)
        #expect(updated?.modifiers.contains(.maskCommand) == false)
    }

    @Test func updateNonexistentHotkeyIsNoOp() {
        let service = HotkeyService()
        let originalCount = service.registeredHotkeys.count

        service.updateHotkey(id: "nonExistent", keyCode: 0x00, modifiers: [.maskCommand])

        #expect(service.registeredHotkeys.count == originalCount)
    }

    // MARK: - Clear Hotkey

    @Test func clearHotkeyUnsetsKeyCode() {
        let service = HotkeyService()

        service.clearHotkey(id: "captureArea")

        let cleared = service.registeredHotkeys.first(where: { $0.id == "captureArea" })
        #expect(cleared != nil)
        #expect(cleared?.keyCode == 0)
        #expect(cleared?.modifiersRawValue == 0)
        #expect(cleared?.isUnassigned == true)
    }

    // MARK: - Restore Defaults

    @Test func restoreDefaultsResetsAll() {
        let service = HotkeyService()

        // Modify some hotkeys
        service.updateHotkey(id: "captureArea", keyCode: 0x00, modifiers: [.maskCommand])
        service.clearHotkey(id: "captureFullscreen")

        // Restore
        service.restoreDefaults()

        // All should match defaults
        for (index, hotkey) in service.registeredHotkeys.enumerated() {
            let defaultHotkey = HotkeyService.defaultHotkeys[index]
            #expect(hotkey.keyCode == defaultHotkey.keyCode,
                    "Hotkey \(hotkey.id) keyCode should be restored")
            #expect(hotkey.modifiersRawValue == defaultHotkey.modifiersRawValue,
                    "Hotkey \(hotkey.id) modifiers should be restored")
        }
    }

    @Test func restoreDefaultsClearsUserDefaults() {
        let service = HotkeyService()

        // Save something, then restore
        service.updateHotkey(id: "captureArea", keyCode: 0x00, modifiers: [.maskCommand])
        service.restoreDefaults()

        #expect(UserDefaults.standard.data(forKey: SettingsKey.customHotkeysData) == nil)
    }

    // MARK: - Conflict Detection

    @Test func conflictDetectionFindsDuplicateCombo() {
        let service = HotkeyService()

        // captureArea is ⌘⇧4 (keyCode 0x15)
        // Check if adding ⌘⇧4 to captureFullscreen would conflict
        let conflict = service.conflictingHotkey(
            keyCode: 0x15,
            modifiers: [.maskCommand, .maskShift],
            excludingId: "captureFullscreen"
        )

        #expect(conflict != nil)
        #expect(conflict?.id == "captureArea")
    }

    @Test func noConflictForSameHotkey() {
        let service = HotkeyService()

        // captureArea is ⌘⇧4 — it should not conflict with itself
        let conflict = service.conflictingHotkey(
            keyCode: 0x15,
            modifiers: [.maskCommand, .maskShift],
            excludingId: "captureArea"
        )

        #expect(conflict == nil, "A hotkey should not conflict with itself")
    }

    @Test func noConflictForUnassignedHotkeys() {
        let service = HotkeyService()

        // Unassigned hotkeys (keyCode 0) should never conflict
        let conflict = service.conflictingHotkey(
            keyCode: 0,
            modifiers: [],
            excludingId: "captureArea"
        )

        #expect(conflict == nil)
    }

    @Test func noConflictForDifferentCombos() {
        let service = HotkeyService()

        // ⌘⇧A is not used by any default hotkey
        let conflict = service.conflictingHotkey(
            keyCode: 0x00,
            modifiers: [.maskCommand, .maskShift],
            excludingId: "captureArea"
        )

        #expect(conflict == nil)
    }

    // MARK: - Persistence Round-Trip

    @Test func persistenceRoundTrip() {
        let service = HotkeyService()

        // Customize a hotkey
        service.updateHotkey(id: "captureArea", keyCode: 0x00, modifiers: [.maskCommand, .maskControl])

        // Create a new service instance and load saved data
        let service2 = HotkeyService()
        service2.loadCustomHotkeys()

        let loaded = service2.registeredHotkeys.first(where: { $0.id == "captureArea" })
        #expect(loaded?.keyCode == 0x00, "Saved keyCode should persist")
        #expect(loaded?.modifiers.contains(.maskCommand) == true)
        #expect(loaded?.modifiers.contains(.maskControl) == true)
        #expect(loaded?.modifiers.contains(.maskShift) == false)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: SettingsKey.customHotkeysData)
    }

    @Test func loadCustomHotkeysPreservesNewDefaults() {
        let service = HotkeyService()

        // Save only one custom hotkey
        service.updateHotkey(id: "captureArea", keyCode: 0x00, modifiers: [.maskCommand])

        // Load into new service — all other hotkeys should keep their defaults
        let service2 = HotkeyService()
        service2.loadCustomHotkeys()

        let fullscreen = service2.registeredHotkeys.first(where: { $0.id == "captureFullscreen" })
        #expect(fullscreen?.keyCode == HotkeyService.Hotkey.captureFullscreen.keyCode,
                "Non-customized hotkeys should retain defaults")

        // Cleanup
        UserDefaults.standard.removeObject(forKey: SettingsKey.customHotkeysData)
    }

    // MARK: - Display String

    @Test func displayStringFormatting() {
        // ⌘⇧4
        let area = HotkeyService.Hotkey.captureArea
        let display = HotkeyService.displayString(for: area)
        #expect(display.contains("⌘"))
        #expect(display.contains("⇧"))
        #expect(display.contains("4"))
    }

    @Test func displayStringForUnassigned() {
        let unassigned = HotkeyService.Hotkey(
            id: "test",
            keyCode: 0,
            modifiers: [],
            label: "Test"
        )
        #expect(HotkeyService.displayString(for: unassigned) == "")
    }

    @Test func displayStringWithAllModifiers() {
        let hotkey = HotkeyService.Hotkey(
            id: "test",
            keyCode: 0x00, // A
            modifiers: [.maskControl, .maskAlternate, .maskShift, .maskCommand],
            label: "Test"
        )
        let display = HotkeyService.displayString(for: hotkey)
        #expect(display == "⌃⌥⇧⌘A")
    }

    // MARK: - Unassigned Hotkey

    @Test func isUnassignedDetection() {
        let assigned = HotkeyService.Hotkey.captureArea
        #expect(assigned.isUnassigned == false)

        let unassigned = HotkeyService.Hotkey(
            id: "test",
            keyCode: 0,
            modifiers: [],
            label: "Test"
        )
        #expect(unassigned.isUnassigned == true)
    }

    @Test func defaultHotkeysCountMatchesRegisteredCount() {
        let service = HotkeyService()
        #expect(service.registeredHotkeys.count == HotkeyService.defaultHotkeys.count)
    }

    // MARK: - Key Code to String

    @Test func keyCodeToStringMapsLetters() {
        #expect(HotkeyService.keyCodeToString(0x00) == "A")
        #expect(HotkeyService.keyCodeToString(0x0D) == "W")
        #expect(HotkeyService.keyCodeToString(0x01) == "S")
    }

    @Test func keyCodeToStringMapsNumbers() {
        #expect(HotkeyService.keyCodeToString(0x15) == "4")
        #expect(HotkeyService.keyCodeToString(0x14) == "3")
        #expect(HotkeyService.keyCodeToString(0x17) == "5")
    }

    @Test func keyCodeToStringMapsSpecialKeys() {
        #expect(HotkeyService.keyCodeToString(0x24) == "↩") // Return
        #expect(HotkeyService.keyCodeToString(0x35) == "⎋") // Escape
        #expect(HotkeyService.keyCodeToString(0x31) == "␣") // Space
    }
}
