import SwiftUI

@main
struct SnapForgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appEnvironment = AppEnvironment()

    var body: some Scene {
        // Menu Bar
        MenuBarExtra {
            MenuBarView()
                .environment(appEnvironment)
        } label: {
            Image(systemName: "hammer.fill")
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
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = AppCoordinator.shared

        // Hide dock icon — menu bar only app
        NSApp.setActivationPolicy(.accessory)

        // Check if first launch
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            coordinator?.showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.cleanup()
    }
}
