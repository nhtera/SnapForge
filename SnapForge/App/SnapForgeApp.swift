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
