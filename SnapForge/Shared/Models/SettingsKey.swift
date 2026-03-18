import Foundation

/// Centralized UserDefaults key constants — eliminates scattered hardcoded strings.
/// Usage: `UserDefaults.standard.bool(forKey: SettingsKey.playSounds)`
enum SettingsKey {
    // Onboarding
    static let hasCompletedOnboarding = "hasCompletedOnboarding"

    // Save Location
    static let saveLocation = "saveLocation"
    static let saveLocationBookmark = "saveLocationBookmark"

    // Screenshots
    static let imageFormat = "imageFormat"
    static let jpegQuality = "jpegQuality"
    static let showMagnifier = "showMagnifier"
    static let showCrosshair = "showCrosshair"
    static let showDimensions = "showDimensions"
    static let captureWindowShadow = "captureWindowShadow"
    static let freezeScreen = "freezeScreen"
    static let timerDelay = "timerDelay"
    static let hideDesktopIcons = "hideDesktopIcons"

    // After-capture actions
    static let autoCopyToClipboard = "autoCopyToClipboard"
    static let autoSave = "autoSave"
    static let showQuickAccess = "showQuickAccess"
    static let openAnnotateAfterCapture = "openAnnotateAfterCapture"
    static let pinAfterCapture = "pinAfterCapture"
    static let playSounds = "playSounds"

    // Recording
    static let recordingFPS = "recordingFPS"
    static let recordingCodec = "recordingCodec"
    static let recordingResolution = "recordingResolution"
    static let showCursorInRecording = "showCursorInRecording"
    static let highlightClicks = "highlightClicks"
    static let showRecordingControls = "showRecordingControls"
    static let showRecordingTimer = "showRecordingTimer"
    static let showRecordingCountdown = "showRecordingCountdown"
    static let dimScreenWhileRecording = "dimScreenWhileRecording"
    static let showKeystrokes = "showKeystrokes"

    // Quick Access
    static let quickAccessTimeout = "quickAccessTimeout"
    static let quickAccessAutoClose = "quickAccessAutoClose"
    static let quickAccessCloseAfterDrag = "quickAccessCloseAfterDrag"

    // GIF
    static let gifFPS = "gifFPS"
    static let gifMaxWidth = "gifMaxWidth"
    static let gifQuality = "gifQuality"
    static let gifLoopCount = "gifLoopCount"

    // Recording Toolbar (Phase 1)
    static let recordingOutputMode = "recordingOutputMode"
    static let recordingSystemAudioEnabled = "recordingSystemAudioEnabled"
    static let recordingMicEnabled = "recordingMicEnabled"
    static let recordingVideoFormat = "recordingVideoFormat"

    // Recording Settings (Phase 4)
    static let recordingCountdownSeconds = "recordingCountdownSeconds"
    static let recordingTimerLimit = "recordingTimerLimit"
    static let autoOpenRecording = "autoOpenRecording"
    static let autoCopyRecording = "autoCopyRecording"

    // Region Overlay (Phase 3)
    static let lastRecordingArea = "lastRecordingArea"

    // Color Picker
    static let colorPickerCopyFormat = "colorPickerCopyFormat"

    // Hotkeys
    static let customHotkeysData = "customHotkeysData"
    static let globalShortcutsEnabled = "globalShortcutsEnabled"
}
