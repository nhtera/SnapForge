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

    init() {
        // Register default settings
        UserDefaults.standard.register(defaults: [
            "hasCompletedOnboarding": false,
            "saveLocation": URL.picturesDirectory.path(),
            // Screenshots
            "imageFormat": "png",
            "jpegQuality": 0.9,
            "showMagnifier": true,
            "showCrosshair": true,
            "showDimensions": true,
            "captureWindowShadow": true,
            "freezeScreen": false,
            "timerDelay": 5,
            "hideDesktopIcons": false,
            // After-capture actions
            "autoCopyToClipboard": true,
            "autoSave": true,
            "showQuickAccess": true,
            "openAnnotateAfterCapture": false,
            "pinAfterCapture": false,
            "playSounds": true,
            // Recording
            "recordingFPS": 30,
            "recordingCodec": "h264",
            "recordingResolution": "retina",
            "showCursorInRecording": true,
            "highlightClicks": false,
            "showRecordingControls": true,
            "showRecordingTimer": true,
            "showRecordingCountdown": false,
            "dimScreenWhileRecording": true,
            "showKeystrokes": false,
            // Quick Access
            "quickAccessTimeout": 5.0,
            "quickAccessAutoClose": false,
            "quickAccessCloseAfterDrag": true,
            // GIF
            "gifFPS": 15,
            "gifMaxWidth": 640,
            "gifQuality": 0.8,
            "gifLoopCount": 0,
        ])
    }
}
