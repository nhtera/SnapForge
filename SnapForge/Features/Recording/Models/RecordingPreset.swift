import Foundation

/// Named recording configuration preset — stores format, quality, audio, overlay settings.
/// Built-in presets cannot be deleted. User presets stored as JSON in UserDefaults.
struct RecordingPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var isBuiltIn: Bool

    var outputMode: String
    var captureMode: String
    var videoFormat: String
    var videoQuality: String
    var systemAudio: Bool
    var microphone: Bool
    var highlightClicks: Bool
    var showKeystrokes: Bool
    var webcamEnabled: Bool

    /// Create preset from current toolbar state (must be called from MainActor)
    @MainActor
    init(name: String, isBuiltIn: Bool = false, from state: RecordingToolbarState) {
        self.id = UUID()
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.outputMode = state.outputMode.rawValue
        self.captureMode = state.captureMode.rawValue
        self.videoFormat = state.videoFormat.rawValue
        self.videoQuality = state.videoQuality.rawValue
        self.systemAudio = state.isSystemAudioEnabled
        self.microphone = state.isMicEnabled
        self.highlightClicks = state.highlightClicks
        self.showKeystrokes = state.showKeystrokes
        self.webcamEnabled = state.webcamEnabled
    }

    /// Memberwise init for built-in presets
    init(id: UUID, name: String, isBuiltIn: Bool, outputMode: String, captureMode: String = "Area",
         videoFormat: String, videoQuality: String, systemAudio: Bool, microphone: Bool,
         highlightClicks: Bool, showKeystrokes: Bool, webcamEnabled: Bool) {
        self.id = id; self.name = name; self.isBuiltIn = isBuiltIn
        self.outputMode = outputMode; self.captureMode = captureMode
        self.videoFormat = videoFormat; self.videoQuality = videoQuality
        self.systemAudio = systemAudio; self.microphone = microphone
        self.highlightClicks = highlightClicks
        self.showKeystrokes = showKeystrokes; self.webcamEnabled = webcamEnabled
    }

    // MARK: - Built-in Presets

    static let builtInPresets: [RecordingPreset] = [
        RecordingPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Tutorial HD", isBuiltIn: true,
            outputMode: "video", videoFormat: "mov", videoQuality: "high",
            systemAudio: true, microphone: true,
            highlightClicks: true, showKeystrokes: true, webcamEnabled: false
        ),
        RecordingPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "GIF Demo", isBuiltIn: true,
            outputMode: "gif", videoFormat: "mov", videoQuality: "high",
            systemAudio: false, microphone: false,
            highlightClicks: true, showKeystrokes: false, webcamEnabled: false
        ),
        RecordingPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "Quick Share", isBuiltIn: true,
            outputMode: "video", videoFormat: "mp4", videoQuality: "medium",
            systemAudio: true, microphone: false,
            highlightClicks: false, showKeystrokes: false, webcamEnabled: false
        ),
    ]

    // MARK: - Persistence

    static func loadAll() -> [RecordingPreset] {
        guard let data = UserDefaults.standard.data(forKey: SettingsKey.recordingPresets),
              let userPresets = try? JSONDecoder().decode([RecordingPreset].self, from: data)
        else { return builtInPresets }
        return builtInPresets + userPresets.filter { !$0.isBuiltIn }
    }

    static func saveUserPresets(_ presets: [RecordingPreset]) {
        let data = try? JSONEncoder().encode(presets.filter { !$0.isBuiltIn })
        UserDefaults.standard.set(data, forKey: SettingsKey.recordingPresets)
    }
}
