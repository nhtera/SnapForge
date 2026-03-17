import AVFoundation
import Foundation

// MARK: - Export Quality

/// Quality presets for video export, mapping to AVAssetExportSession presets.
enum ExportQuality: String, CaseIterable, Identifiable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var id: String { rawValue }

    /// Maps to AVAssetExportSession preset
    var exportPreset: String {
        switch self {
        case .low: AVAssetExportPresetMediumQuality
        case .medium: AVAssetExportPreset1920x1080
        case .high: AVAssetExportPresetHighestQuality
        }
    }

    /// Bitrate multiplier for file size estimation
    var bitrateMultiplier: Float {
        switch self {
        case .low: 0.3
        case .medium: 0.6
        case .high: 1.0
        }
    }
}

// MARK: - Audio Export Mode

/// Audio handling mode for video export.
enum AudioExportMode: String, CaseIterable, Identifiable {
    case keep = "Keep Original"
    case mute = "Mute"
    case custom = "Custom Volume"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .keep: "speaker.wave.2"
        case .mute: "speaker.slash"
        case .custom: "slider.horizontal.3"
        }
    }
}

// MARK: - Export Dimension Preset

/// Dimension presets for resizing exported video.
enum ExportDimensionPreset: String, CaseIterable, Identifiable {
    case original = "Original"
    case percent90 = "90%"
    case percent80 = "80%"
    case percent60 = "60%"
    case percent50 = "50%"
    case percent40 = "40%"
    case percent30 = "30%"
    case percent20 = "20%"
    case custom = "Custom"

    var id: String { rawValue }

    /// Returns scale factor for percentage-based presets
    var scaleFactor: CGFloat? {
        switch self {
        case .percent90: 0.90
        case .percent80: 0.80
        case .percent60: 0.60
        case .percent50: 0.50
        case .percent40: 0.40
        case .percent30: 0.30
        case .percent20: 0.20
        default: nil
        }
    }

    /// Display label showing dimensions when available
    func displayLabel(for naturalSize: CGSize) -> String {
        guard naturalSize.width > 0 && naturalSize.height > 0 else { return rawValue }

        switch self {
        case .original:
            return "Original (\(Int(naturalSize.width))×\(Int(naturalSize.height)))"
        case .percent90, .percent80, .percent60, .percent50, .percent40, .percent30, .percent20:
            guard let scale = scaleFactor else { return rawValue }
            let width = Int(naturalSize.width * scale)
            let height = Int(naturalSize.height * scale)
            let evenWidth = width - (width % 2)
            let evenHeight = height - (height % 2)
            return "\(rawValue) (\(evenWidth)×\(evenHeight))"
        case .custom:
            return "Custom"
        }
    }
}

// MARK: - Export Settings Container

/// Combined export configuration for quality, dimensions, and audio.
struct ExportSettings: Equatable {
    var quality: ExportQuality = .high
    var dimensionPreset: ExportDimensionPreset = .original
    var customWidth: Int = 1920
    var customHeight: Int = 1080
    var aspectRatioLocked: Bool = true
    var audioMode: AudioExportMode = .keep
    var audioVolume: Float = 1.0 // 0.0 to 2.0 (0% to 200%)

    /// Compute actual export dimensions for video content.
    func exportSize(from naturalSize: CGSize) -> CGSize {
        switch dimensionPreset {
        case .original:
            return naturalSize

        case .percent90, .percent80, .percent60, .percent50, .percent40, .percent30, .percent20:
            guard let scale = dimensionPreset.scaleFactor else { return naturalSize }
            var targetWidth = Int(naturalSize.width * scale)
            var targetHeight = Int(naturalSize.height * scale)
            // Ensure even dimensions for video encoding
            targetWidth = targetWidth - (targetWidth % 2)
            targetHeight = targetHeight - (targetHeight % 2)
            return CGSize(width: targetWidth, height: targetHeight)

        case .custom:
            let evenWidth = customWidth - (customWidth % 2)
            let evenHeight = customHeight - (customHeight % 2)
            return CGSize(width: evenWidth, height: evenHeight)
        }
    }

    /// Check if audio should be included in export
    var shouldIncludeAudio: Bool {
        audioMode != .mute
    }

    /// Get effective volume (0.0 to 2.0)
    var effectiveVolume: Float {
        switch audioMode {
        case .keep: 1.0
        case .mute: 0.0
        case .custom: audioVolume
        }
    }
}
