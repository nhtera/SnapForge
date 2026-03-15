import SwiftUI

@main
struct SnapForgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appEnvironment = AppEnvironment.shared

    var body: some Scene {
        // Menu Bar
        MenuBarExtra {
            MenuBarView()
                .environment(appEnvironment)
        } label: {
            Image(systemName: appEnvironment.menuBarIconName)
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)

        // Settings Window
        Settings {
            SettingsView()
                .environment(appEnvironment)
        }
    }
}

// MARK: - App Delegate
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = AppCoordinator.shared

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

