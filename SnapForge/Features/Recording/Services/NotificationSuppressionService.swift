import Foundation
import AppKit

/// Automatically suppresses macOS notifications (Do Not Disturb / Focus mode)
/// during screen recording and restores original state when recording stops.
///
/// Uses Shortcuts.app integration for sandbox-safe DND toggling on macOS 15+.
/// Requires user to create two Shortcuts: "SnapForge DND On" and "SnapForge DND Off".
/// If shortcuts are not configured, the feature silently degrades — no crash.
@MainActor
@Observable
final class NotificationSuppressionService {
    static let shared = NotificationSuppressionService()

    /// Whether DND was already enabled before we toggled it
    private var wasDNDEnabledBefore = false

    /// Whether we currently have DND suppressed
    private(set) var isSuppressing = false

    private init() {}

    // MARK: - Public API

    /// Enable notification suppression if the user setting allows it.
    /// Runs DND toggle on a background thread to avoid blocking UI.
    func enableSuppression() {
        guard UserDefaults.standard.bool(forKey: SettingsKey.suppressNotificationsWhileRecording) else { return }
        guard !isSuppressing else { return }

        isSuppressing = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            let wasEnabled = await Task.detached { self.checkDNDState() }.value
            self.wasDNDEnabledBefore = wasEnabled
            if !wasEnabled {
                await Task.detached { self.runShortcut("SnapForge DND On") }.value
            }
            AppLogger.recording.info("Notification suppression enabled (DND was \(wasEnabled ? "already on" : "off"))")
        }
    }

    /// Disable notification suppression, restoring original DND state.
    /// Only disables DND if we were the ones who enabled it.
    func disableSuppression() {
        guard isSuppressing else { return }
        let shouldRestore = !wasDNDEnabledBefore
        isSuppressing = false

        if shouldRestore {
            Task { @MainActor in
                await Task.detached { self.runShortcut("SnapForge DND Off") }.value
                AppLogger.recording.info("Notification suppression disabled")
            }
        }
    }

    // MARK: - Private

    /// Check if DND/Focus is currently enabled by reading ControlCenter defaults.
    /// Runs on a background thread.
    private nonisolated func checkDNDState() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", "com.apple.controlcenter", "NSStatusItem Visible FocusModes"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return false }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return output == "1"
        } catch {
            return false
        }
    }

    /// Run a named Shortcut via the shortcuts CLI.
    /// Gracefully fails if shortcut doesn't exist or sandbox blocks execution.
    private nonisolated func runShortcut(_ name: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // Shortcut not found or sandbox blocked — silently degrade
        }
    }
}
