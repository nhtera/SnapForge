import SwiftUI

/// Settings window with tabbed layout for SnapForge preferences.
/// Tabs: General, Screenshots, Recording, Quick Access, Shortcuts, Permissions, About
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape.fill") {
                GeneralSettingsTab()
            }

            Tab("Screenshots", systemImage: "camera.fill") {
                ScreenshotsSettingsTab()
            }

            Tab("Recording", systemImage: "video.fill") {
                RecordingSettingsTab()
            }

            Tab("Quick Access", systemImage: "rectangle.portrait.and.arrow.forward") {
                QuickAccessSettingsTab()
            }

            Tab("Shortcuts", systemImage: "command") {
                ShortcutsSettingsTab()
            }

            Tab("Permissions", systemImage: "lock.shield") {
                PermissionsSettingsTab()
            }

            Tab("About", systemImage: "info.circle") {
                AboutSettingsTab()
            }
        }
        .frame(width: 560, height: 480)
    }
}
