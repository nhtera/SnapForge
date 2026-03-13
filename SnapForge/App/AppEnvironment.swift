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
            "freezeScreen": false,
            "timerDelay": 5,
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
            "showCursorInRecording": true,
            "highlightClicks": false,
            // Quick Access
            "quickAccessTimeout": 5.0,
            // GIF
            "gifFPS": 15,
            "gifMaxWidth": 640,
        ])
    }
}
