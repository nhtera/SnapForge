import Sparkle
import AppKit

/// Shared Sparkle updater manager — singleton, starts updater once, logs lifecycle.
/// Conforms to SPUStandardUserDriverDelegate to ensure update alerts center on the Settings window.
@MainActor
final class UpdaterManager: NSObject, SPUUpdaterDelegate {
    static let shared = UpdaterManager()

    private(set) var controller: SPUStandardUpdaterController!
    private let driverDelegate = UpdaterDriverDelegate()

    var updater: SPUUpdater {
        controller.updater
    }

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: driverDelegate
        )
        print("✅ Sparkle updater initialized")
    }

    func checkForUpdates() {
        // Find and activate the Settings window so Sparkle centers its alert on it
        if let settingsWindow = NSApp.windows.first(where: { $0.title == "Settings" || $0.title.contains("About") }) {
            settingsWindow.makeKeyAndOrderFront(nil)
            settingsWindow.center()
        }
        NSApp.activate(ignoringOtherApps: true)

        // Small delay to let the window become key before Sparkle shows its alert
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            print("🔄 Manual check for updates triggered")
            updater.checkForUpdates()
        }
    }

    // MARK: - SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        let count = appcast.items.count
        print("✅ Appcast loaded: \(count) item(s)")
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        print("✅ Update available: v\(item.displayVersionString) (\(item.versionString))")
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        print("ℹ️ No update found: \(error.localizedDescription)")
    }

    nonisolated func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        print("✅ Downloaded update: v\(item.displayVersionString)")
    }

    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        print("✅ Installing update: v\(item.displayVersionString)")
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let nsError = error as NSError
        print("❌ Update aborted: \(nsError.localizedDescription) [code=\(nsError.code)]")
    }

    nonisolated func updater(_ updater: SPUUpdater, didCancelInstallUpdateOnQuit item: SUAppcastItem) {
        print("⚠️ User cancelled install on quit: v\(item.displayVersionString)")
    }
}

// MARK: - SPUStandardUserDriverDelegate (non-isolated to avoid actor crossing)

final class UpdaterDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }
}
