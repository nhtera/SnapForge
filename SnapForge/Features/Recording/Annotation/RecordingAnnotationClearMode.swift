import Foundation

/// Auto-clear mode for recording annotations per tool
enum RecordingAnnotationClearMode: Hashable, Equatable {
    case persist
    case timeBased(seconds: Double)
    case countBased(count: Int)

    var displayName: String {
        switch self {
        case .persist: return "Persist"
        case .timeBased(let s): return "\(Int(s))s"
        case .countBased(let c): return "Last \(c)"
        }
    }

    /// Preset options for the auto-clear menu
    static let presets: [RecordingAnnotationClearMode] = [
        .persist,
        .timeBased(seconds: 3),
        .timeBased(seconds: 5),
        .timeBased(seconds: 10),
        .countBased(count: 3),
        .countBased(count: 5),
        .countBased(count: 10),
    ]
}
