import SwiftUI

/// Dependency injection container using @Observable (macOS 14+).
/// Provides shared access to all global services.
@MainActor
@Observable
final class AppEnvironment {
    static let shared = AppEnvironment()
    // MARK: - Services
    let permissionService = PermissionService()
    let hotkeyService = HotkeyService()
    let exportService = ExportService()
    let clipboardService = ClipboardService()
    let storageService = StorageService()

    // MARK: - App State
    var isRecording = false
    var lastCapture: NSImage?
    var captureCount: Int = 0

    /// Menu bar icon name — changes during OCR processing and recording for visual feedback
    var menuBarIconName: String = "viewfinder"

    /// Formatted recording timer shown in menu bar (e.g. "02:45")
    var menuBarRecordingTimer: String = ""

    // MARK: - Error Feedback

    /// Last user-facing error message; cleared automatically after display timeout
    var lastErrorMessage: String?
    var isShowingError = false
    private var errorDismissTask: Task<Void, Never>?

    /// Show a user-facing error banner for 4 seconds, then auto-dismiss.
    func showUserError(_ message: String) {
        errorDismissTask?.cancel()
        lastErrorMessage = message
        isShowingError = true
        errorDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            isShowingError = false
        }
    }

    init() {
        // Register default settings
        UserDefaults.standard.register(defaults: [
            SettingsKey.hasCompletedOnboarding: false,
            // saveLocation default omitted — resolved by SandboxFileAccessManager
            // to avoid sandbox container path (~/Library/Containers/.../Pictures)
            // Screenshots
            SettingsKey.imageFormat: "png",
            SettingsKey.jpegQuality: 0.9,
            SettingsKey.showMagnifier: true,
            SettingsKey.showCrosshair: true,
            SettingsKey.showDimensions: true,
            SettingsKey.captureWindowShadow: true,
            SettingsKey.freezeScreen: false,
            SettingsKey.timerDelay: 5,
            SettingsKey.hideDesktopIcons: false,
            // After-capture actions
            SettingsKey.autoCopyToClipboard: true,
            SettingsKey.autoSave: true,
            SettingsKey.showQuickAccess: true,
            SettingsKey.openAnnotateAfterCapture: false,
            SettingsKey.pinAfterCapture: false,
            SettingsKey.playSounds: true,
            // Recording
            SettingsKey.recordingFPS: 30,
            SettingsKey.recordingCodec: "h264",
            SettingsKey.recordingResolution: "retina",
            SettingsKey.showCursorInRecording: true,
            SettingsKey.highlightClicks: false,
            SettingsKey.showRecordingControls: true,
            SettingsKey.showRecordingTimer: true,
            SettingsKey.showRecordingCountdown: false,
            SettingsKey.dimScreenWhileRecording: true,
            SettingsKey.showKeystrokes: false,
            // Quick Access
            SettingsKey.quickAccessTimeout: 5.0,
            SettingsKey.quickAccessAutoClose: false,
            SettingsKey.quickAccessCloseAfterDrag: true,
            // GIF
            SettingsKey.gifFPS: 15,
            SettingsKey.gifMaxWidth: 640,
            SettingsKey.gifQuality: 0.8,
            SettingsKey.gifLoopCount: 0,
            // Phase 1 Enhancements
            SettingsKey.suppressNotificationsWhileRecording: true,
            SettingsKey.countdownSoundEnabled: true,
            SettingsKey.showEstimatedFileSize: true,
            SettingsKey.showRecordingTimeInMenuBar: false,
            // Color Picker
            SettingsKey.colorPickerCopyFormat: "hex",
            // Hotkeys
            SettingsKey.globalShortcutsEnabled: true,
        ])
    }
}
