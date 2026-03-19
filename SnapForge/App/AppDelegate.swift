import SwiftUI

/// App Delegate — handles app lifecycle, hotkey registration, and cleanup.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = AppCoordinator.shared

        // UI test mode: show annotation editor with test image, skip normal startup
        if ProcessInfo.processInfo.arguments.contains("--ui-test") {
            NSApp.setActivationPolicy(.regular)
            let testImage = NSImage(size: NSSize(width: 800, height: 600))
            testImage.lockFocus()
            NSColor.darkGray.setFill()
            NSBezierPath.fill(NSRect(x: 0, y: 0, width: 800, height: 600))
            testImage.unlockFocus()
            coordinator?.showAnnotationEditor(for: testImage)
            return
        }

        // Hide dock icon — menu bar only app
        NSApp.setActivationPolicy(.accessory)

        // Check if first launch
        if !UserDefaults.standard.bool(forKey: SettingsKey.hasCompletedOnboarding) {
            coordinator?.showOnboarding()
        }

        // Register global hotkeys
        registerHotkeys()
    }

    private func registerHotkeys() {
        let hotkeys = AppEnvironment.shared.hotkeyService
        hotkeys.loadCustomHotkeys()

        hotkeys.register(hotkey: .captureArea) { @Sendable in
            Task { @MainActor in
                CaptureSessionManager.shared.startCapture(mode: .area)
            }
        }
        hotkeys.register(hotkey: .captureFullscreen) { @Sendable in
            Task { @MainActor in
                CaptureSessionManager.shared.startCapture(mode: .fullscreen)
            }
        }
        hotkeys.register(hotkey: .captureWindow) { @Sendable in
            Task { @MainActor in
                CaptureSessionManager.shared.startCapture(mode: .window)
            }
        }
        hotkeys.register(hotkey: .selfTimer) { @Sendable in
            Task { @MainActor in
                CaptureSessionManager.shared.startCapture(mode: .timedArea)
            }
        }
        hotkeys.register(hotkey: .startRecording) { @Sendable in
            Task { @MainActor in
                AppCoordinator.shared.toggleRecording()
            }
        }
        hotkeys.register(hotkey: .toggleOCR) { @Sendable in
            Task { @MainActor in
                CaptureSessionManager.shared.startCapture(mode: .ocrCapture)
            }
        }
        hotkeys.register(hotkey: .colorPicker) { @Sendable in
            Task { @MainActor in
                await ColorPickerService.shared.pickAndCopy()
            }
        }
        hotkeys.register(hotkey: .scrollCapture) { @Sendable in
            Task { @MainActor in
                CaptureSessionManager.shared.startCapture(mode: .scrollCapture)
            }
        }

        hotkeys.startListening()
        print("⌨️ Global hotkeys registered and listening")
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppEnvironment.shared.hotkeyService.stopListening()
        coordinator?.cleanup()
    }
}
