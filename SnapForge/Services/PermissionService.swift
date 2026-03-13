import Foundation
import AppKit
import ScreenCaptureKit
import AVFoundation

/// Manages macOS TCC permissions: Screen Recording, Microphone, Camera, Accessibility.
@MainActor
@Observable
final class PermissionService {

    enum PermissionStatus: String, Sendable {
        case granted = "Granted"
        case denied = "Denied"
        case notDetermined = "Not Determined"
    }

    var screenRecordingStatus: PermissionStatus = .notDetermined
    var microphoneStatus: PermissionStatus = .notDetermined
    var cameraStatus: PermissionStatus = .notDetermined
    var accessibilityStatus: PermissionStatus = .notDetermined

    init() {
        refreshAll()
    }

    // MARK: - Refresh All

    func refreshAll() {
        checkScreenRecording()
        checkMicrophone()
        checkCamera()
        checkAccessibility()
    }

    // MARK: - Screen Recording

    func checkScreenRecording() {
        Task {
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                self.screenRecordingStatus = .granted
            } catch {
                self.screenRecordingStatus = .denied
            }
        }
    }

    func requestScreenRecording() {
        // Open System Settings → Privacy → Screen Recording
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Microphone

    func checkMicrophone() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneStatus = .granted
        case .denied, .restricted:
            microphoneStatus = .denied
        case .notDetermined:
            microphoneStatus = .notDetermined
        @unknown default:
            microphoneStatus = .notDetermined
        }
    }

    func requestMicrophone() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphoneStatus = granted ? .granted : .denied
    }

    // MARK: - Camera

    func checkCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraStatus = .granted
        case .denied, .restricted:
            cameraStatus = .denied
        case .notDetermined:
            cameraStatus = .notDetermined
        @unknown default:
            cameraStatus = .notDetermined
        }
    }

    func requestCamera() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        cameraStatus = granted ? .granted : .denied
    }

    // MARK: - Accessibility

    func checkAccessibility() {
        let isAccessibilityEnabled = AXIsProcessTrusted()
        accessibilityStatus = isAccessibilityEnabled ? .granted : .denied
    }

    func requestAccessibility() {
        // Use the raw key string to avoid Swift 6 concurrency issue with kAXTrustedCheckOptionPrompt global var
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Helpers

    var allCriticalPermissionsGranted: Bool {
        screenRecordingStatus == .granted
    }

    var allPermissionsGranted: Bool {
        screenRecordingStatus == .granted &&
        microphoneStatus == .granted &&
        cameraStatus == .granted &&
        accessibilityStatus == .granted
    }
}

