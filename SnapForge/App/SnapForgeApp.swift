import SwiftUI

@main
struct SnapForgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appEnvironment = AppEnvironment.shared
    @AppStorage(SettingsKey.showRecordingTimeInMenuBar) private var showTimeInMenuBar = true

    var body: some Scene {
        // Menu Bar
        MenuBarExtra {
            MenuBarView()
                .environment(appEnvironment)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: appEnvironment.menuBarIconName)
                    .symbolRenderingMode(appEnvironment.isRecording ? .multicolor : .hierarchical)
                    .foregroundStyle(appEnvironment.isRecording ? .red : .primary)
                if showTimeInMenuBar, !appEnvironment.menuBarRecordingTimer.isEmpty {
                    Text(appEnvironment.menuBarRecordingTimer)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)

        // Settings Window
        Settings {
            SettingsView()
                .environment(appEnvironment)
        }
    }
}
