import AppKit
import Foundation
import os.log

private let logger = Logger(subsystem: "SnapForge", category: "SandboxFileAccess")

/// Manages security-scoped bookmark persistence and scoped file access for sandbox mode.
@MainActor
final class SandboxFileAccessManager {
    static let shared = SandboxFileAccessManager()

    private let defaults = UserDefaults.standard
    private var didPromptThisSession = false

    private init() {}

    /// Scoped access token — call `stop()` when file operation completes.
    struct ScopedAccess: Sendable {
        let url: URL
        private let accessURL: URL
        private let didStartAccessing: Bool

        init(url: URL, accessURL: URL, didStartAccessing: Bool) {
            self.url = url
            self.accessURL = accessURL
            self.didStartAccessing = didStartAccessing
        }

        nonisolated func stop() {
            if didStartAccessing {
                accessURL.stopAccessingSecurityScopedResource()
            }
        }
    }

    // MARK: - Default Directory

    /// Real Pictures/SnapForge directory (for NSOpenPanel default location).
    /// Uses `getpwuid` to bypass sandbox container redirect.
    var defaultPicturesDirectory: URL {
        if let pw = getpwuid(getuid()), let homeDir = pw.pointee.pw_dir {
            let realHome = String(cString: homeDir)
            return URL(fileURLWithPath: realHome)
                .appendingPathComponent("Pictures", isDirectory: true)
                .appendingPathComponent("SnapForge", isDirectory: true)
        }
        // Fallback — container path (still functional, just shows sandbox path on drag)
        return URL.picturesDirectory
            .appendingPathComponent("SnapForge", isDirectory: true)
    }

    // MARK: - Bookmark Resolution

    /// Resolve the persisted export bookmark URL. Returns nil if no valid bookmark exists.
    func resolveBookmarkURL() -> URL? {
        guard let data = defaults.data(forKey: SettingsKey.saveLocationBookmark) else { return nil }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ).standardizedFileURL

            if isStale {
                _ = saveBookmark(for: url)
            }
            return url
        } catch {
            logger.error("Failed to resolve bookmark: \(error.localizedDescription, privacy: .public)")
            defaults.removeObject(forKey: SettingsKey.saveLocationBookmark)
            return nil
        }
    }

    /// Persist a security-scoped bookmark for the given URL.
    @discardableResult
    func saveBookmark(for url: URL) -> Bool {
        do {
            let data = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(url.path, forKey: SettingsKey.saveLocation)
            defaults.set(data, forKey: SettingsKey.saveLocationBookmark)
            didPromptThisSession = false
            return true
        } catch {
            logger.error("Failed to save bookmark: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Whether a valid, usable bookmark exists.
    var hasValidBookmark: Bool {
        guard let url = resolveBookmarkURL() else { return false }
        let didStart = url.startAccessingSecurityScopedResource()
        if didStart { url.stopAccessingSecurityScopedResource() }
        return didStart
    }

    // MARK: - Folder Picker

    /// Show NSOpenPanel to let user grant folder access. Returns selected URL or nil.
    @discardableResult
    func chooseExportDirectory(
        message: String = "Choose where SnapForge saves captures",
        prompt: String = "Grant Access",
        directoryURL: URL? = nil
    ) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = message
        panel.prompt = prompt
        panel.directoryURL = directoryURL ?? defaultPicturesDirectory

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return nil }
        guard saveBookmark(for: selectedURL) else { return nil }
        return selectedURL.standardizedFileURL
    }

    /// Ensure we have export directory access. Prompts user if no valid bookmark.
    func ensureExportAccess() -> URL? {
        if hasValidBookmark, let url = resolveBookmarkURL() {
            return url
        }

        guard !didPromptThisSession else { return nil }
        didPromptThisSession = true

        return chooseExportDirectory()
    }

    // MARK: - Scoped Access

    /// Begin security-scoped access to a URL. Always call `stop()` on the returned token.
    func beginAccessingURL(_ targetURL: URL) -> ScopedAccess {
        // Try bookmark scope first (covers child paths under the bookmarked directory)
        if let bookmarkURL = resolveBookmarkURL() {
            let targetPath = targetURL.standardizedFileURL.resolvingSymlinksInPath().path
            let bookmarkPath = bookmarkURL.standardizedFileURL.resolvingSymlinksInPath().path

            if targetPath == bookmarkPath || targetPath.hasPrefix(bookmarkPath + "/") {
                let didStart = bookmarkURL.startAccessingSecurityScopedResource()
                if didStart {
                    return ScopedAccess(url: targetURL, accessURL: bookmarkURL, didStartAccessing: true)
                }
            }
        }

        // Fallback: try direct access on the target URL
        let didStart = targetURL.startAccessingSecurityScopedResource()
        if !didStart && isRunningSandboxed {
            logger.error("Failed scoped access for: \(targetURL.path, privacy: .public)")
        }
        return ScopedAccess(url: targetURL, accessURL: targetURL, didStartAccessing: didStart)
    }

    /// Execute a closure with scoped access to a URL.
    func withScopedAccess<T>(to url: URL, _ operation: () throws -> T) rethrows -> T {
        let access = beginAccessingURL(url)
        defer { access.stop() }
        return try operation()
    }

    // MARK: - Private

    private var isRunningSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }
}
