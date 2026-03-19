import SwiftUI

/// Centralized observable state for recording toolbars.
/// Persists all settings to UserDefaults via SettingsKey.
@MainActor @Observable
final class RecordingToolbarState {
    /// Suppresses didSet UserDefaults writes during batch reload
    private var isReloading = false

    var outputMode: RecordingOutputMode {
        didSet { guard !isReloading else { return }; UserDefaults.standard.set(outputMode.rawValue, forKey: SettingsKey.recordingOutputMode) }
    }
    var captureMode: RecordingMode = .area
    var isSystemAudioEnabled: Bool {
        didSet { guard !isReloading else { return }; UserDefaults.standard.set(isSystemAudioEnabled, forKey: SettingsKey.recordingSystemAudioEnabled) }
    }
    var isMicEnabled: Bool {
        didSet { guard !isReloading else { return }; UserDefaults.standard.set(isMicEnabled, forKey: SettingsKey.recordingMicEnabled) }
    }
    var showOptionsPopover: Bool = false
    /// Aspect ratio constraint (session-only, not persisted)
    var aspectRatio: RecordingAspectRatio = .free
    /// Size preset (session-only)
    var sizePreset: RecordingSizePreset = .custom
    /// Callback when aspect ratio changes
    var onAspectRatioChanged: ((RecordingAspectRatio) -> Void)?
    /// Callback when size preset selected
    var onSizePresetSelected: ((CGSize) -> Void)?

    var videoFormat: VideoFormat {
        didSet { guard !isReloading else { return }; UserDefaults.standard.set(videoFormat.rawValue, forKey: SettingsKey.recordingVideoFormat) }
    }
    var videoQuality: VideoQuality {
        didSet { guard !isReloading else { return }; UserDefaults.standard.set(videoQuality.rawValue, forKey: SettingsKey.recordingVideoQuality) }
    }
    var highlightClicks: Bool {
        didSet { guard !isReloading else { return }; UserDefaults.standard.set(highlightClicks, forKey: SettingsKey.highlightClicks) }
    }
    var showKeystrokes: Bool {
        didSet { guard !isReloading else { return }; UserDefaults.standard.set(showKeystrokes, forKey: SettingsKey.showKeystrokes) }
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
        let qualRaw = defaults.string(forKey: SettingsKey.recordingVideoQuality) ?? "high"
        videoQuality = VideoQuality(rawValue: qualRaw) ?? .high
        highlightClicks = defaults.bool(forKey: SettingsKey.highlightClicks)
        showKeystrokes = defaults.bool(forKey: SettingsKey.showKeystrokes)
    }

    /// Re-read all persistent properties from UserDefaults (for sync with Settings window)
    func reloadFromDefaults() {
        isReloading = true
        defer { isReloading = false }
        let defaults = UserDefaults.standard
        let fmtRaw = defaults.string(forKey: SettingsKey.recordingVideoFormat) ?? "mov"
        videoFormat = VideoFormat(rawValue: fmtRaw) ?? .mov
        let qualRaw = defaults.string(forKey: SettingsKey.recordingVideoQuality) ?? "high"
        videoQuality = VideoQuality(rawValue: qualRaw) ?? .high
        isSystemAudioEnabled = defaults.object(forKey: SettingsKey.recordingSystemAudioEnabled) == nil
            ? true : defaults.bool(forKey: SettingsKey.recordingSystemAudioEnabled)
        isMicEnabled = defaults.bool(forKey: SettingsKey.recordingMicEnabled)
        highlightClicks = defaults.bool(forKey: SettingsKey.highlightClicks)
        showKeystrokes = defaults.bool(forKey: SettingsKey.showKeystrokes)
    }
}
