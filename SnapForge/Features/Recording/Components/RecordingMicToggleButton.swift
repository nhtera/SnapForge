import SwiftUI
import AVFoundation

/// Mic on/off toggle button for recording toolbar
struct RecordingMicToggleButton: View {
    @Bindable var state: RecordingToolbarState

    var body: some View {
        RecordingToolbarIconButton(
            systemName: state.isMicEnabled ? "mic.fill" : "mic.slash",
            action: handleToggle,
            accessibilityLabel: state.isMicEnabled ? "Disable microphone" : "Enable microphone",
            isSelected: state.isMicEnabled
        )
    }

    private func handleToggle() {
        if state.isMicEnabled {
            state.isMicEnabled = false
            return
        }
        // Request mic permission before enabling
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            state.isMicEnabled = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    state.isMicEnabled = granted
                }
            }
        case .denied, .restricted:
            // Show system settings alert
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        @unknown default:
            break
        }
    }
}
