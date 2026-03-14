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

    /// Menu bar icon name — changes during OCR processing for visual feedback
    var menuBarIconName: String = "hammer.fill"

    init() {
        // Register default settings
        UserDefaults.standard.register(defaults: [
            SettingsKey.hasCompletedOnboarding: false,
            SettingsKey.saveLocation: URL.picturesDirectory.path(),
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
            // Color Picker
            SettingsKey.colorPickerCopyFormat: "hex",
        ])
    }
}
