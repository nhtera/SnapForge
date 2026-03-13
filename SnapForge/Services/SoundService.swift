import AppKit

/// Centralized sound playback — replaces scattered `NSSound` calls across the codebase.
/// Each method respects the `playSounds` user preference.
enum SoundService {

    /// "Glass" — after successful capture
    static func playCapture() {
        guard UserDefaults.standard.bool(forKey: SettingsKey.playSounds) else { return }
        NSSound(named: .init("Glass"))?.play()
    }

    /// "Tink" — when showing overlay or countdown
    static func playTink() {
        guard UserDefaults.standard.bool(forKey: SettingsKey.playSounds) else { return }
        NSSound(named: .init("Tink"))?.play()
    }

    /// "Basso" — error or empty OCR result
    static func playError() {
        NSSound(named: .init("Basso"))?.play()
    }
}
