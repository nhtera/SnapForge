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
            "saveLocation": NSSearchPathForDirectoriesInDomains(.picturesDirectory, .userDomainMask, true).first ?? "~/Pictures",
            "imageFormat": "png",
            "jpegQuality": 0.9,
            "showQuickAccess": true,
            "quickAccessTimeout": 5.0,
            "autoCopyToClipboard": true,
            "showMagnifier": true,
            "showCrosshair": true,
            "recordingFPS": 30,
            "recordingCodec": "h264",
            "gifFPS": 15,
            "gifMaxWidth": 640,
        ])
    }
}
