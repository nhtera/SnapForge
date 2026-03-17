import Sparkle

/// Shared Sparkle updater manager — singleton, starts updater once, logs lifecycle.
@MainActor
final class UpdaterManager: NSObject, SPUUpdaterDelegate {
    static let shared = UpdaterManager()

    private(set) var controller: SPUStandardUpdaterController!

    var updater: SPUUpdater {
        controller.updater
    }

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        print("✅ Sparkle updater initialized")
    }

    func checkForUpdates() {
        print("🔄 Manual check for updates triggered")
        updater.checkForUpdates()
    }

    // MARK: - SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        let count = appcast.items.count
        print("✅ Appcast loaded: \(count) item(s)")
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString ?? "?"
        let build = item.versionString ?? "?"
        print("✅ Update available: v\(version) (\(build))")
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        print("ℹ️ No update found: \(error.localizedDescription)")
    }

    nonisolated func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        let version = item.displayVersionString ?? "?"
        print("✅ Downloaded update: v\(version)")
    }

    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        let version = item.displayVersionString ?? "?"
        print("✅ Installing update: v\(version)")
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let nsError = error as NSError
        print("❌ Update aborted: \(nsError.localizedDescription) [code=\(nsError.code)]")
    }

    nonisolated func updater(_ updater: SPUUpdater, didCancelInstallUpdateOnQuit item: SUAppcastItem) {
        let version = item.displayVersionString ?? "?"
        print("⚠️ User cancelled install on quit: v\(version)")
    }
}
