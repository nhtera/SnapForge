import SwiftUI

/// Centralized observable state for recording toolbars.
/// Persists all settings to UserDefaults via SettingsKey.
@MainActor @Observable
final class RecordingToolbarState {
    var outputMode: RecordingOutputMode {
        didSet { UserDefaults.standard.set(outputMode.rawValue, forKey: SettingsKey.recordingOutputMode) }
    }
    var captureMode: RecordingMode = .area
    var isSystemAudioEnabled: Bool {
        didSet { UserDefaults.standard.set(isSystemAudioEnabled, forKey: SettingsKey.recordingSystemAudioEnabled) }
    }
    var isMicEnabled: Bool {
        didSet { UserDefaults.standard.set(isMicEnabled, forKey: SettingsKey.recordingMicEnabled) }
    }
    var showOptionsPopover: Bool = false

    var videoFormat: VideoFormat {
        didSet { UserDefaults.standard.set(videoFormat.rawValue, forKey: SettingsKey.recordingVideoFormat) }
    }
    var videoQuality: VideoQuality = .high
    var highlightClicks: Bool {
        didSet { UserDefaults.standard.set(highlightClicks, forKey: SettingsKey.highlightClicks) }
    }
    var showKeystrokes: Bool {
        didSet { UserDefaults.standard.set(showKeystrokes, forKey: SettingsKey.showKeystrokes) }
    }

    /// Callback when capture mode changes (area/fullscreen)
    var onCaptureModeChanged: ((RecordingMode) -> Void)?

    init() {
        let defaults = UserDefaults.standard
        let modeRaw = defaults.string(forKey: SettingsKey.recordingOutputMode) ?? "video"
        outputMode = RecordingOutputMode(rawValue: modeRaw) ?? .video
        // System audio defaults to true if key not explicitly set
        isSystemAudioEnabled = defaults.object(forKey: SettingsKey.recordingSystemAudioEnabled) == nil
            ? true
            : defaults.bool(forKey: SettingsKey.recordingSystemAudioEnabled)
        isMicEnabled = defaults.bool(forKey: SettingsKey.recordingMicEnabled)
        let fmtRaw = defaults.string(forKey: SettingsKey.recordingVideoFormat) ?? "mov"
        videoFormat = VideoFormat(rawValue: fmtRaw) ?? .mov
        highlightClicks = defaults.bool(forKey: SettingsKey.highlightClicks)
        showKeystrokes = defaults.bool(forKey: SettingsKey.showKeystrokes)
    }
}
