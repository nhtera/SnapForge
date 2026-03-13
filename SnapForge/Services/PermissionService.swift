import Foundation
import AppKit
@preconcurrency import ScreenCaptureKit
import AVFoundation

/// Manages macOS TCC permissions: Screen Recording, Microphone, Camera, Accessibility.

enum PermissionError: LocalizedError {
    case screenRecordingDenied

    var errorDescription: String? {
        switch self {
        case .screenRecordingDenied:
            return "Screen recording permission is required. Please grant access in System Settings."
        }
    }
}

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
        // Use CGPreflightScreenCaptureAccess (macOS 10.15+) — lightweight check
        // that does NOT trigger macOS 15's re-consent dialog like SCShareableContent does
        if CGPreflightScreenCaptureAccess() {
            screenRecordingStatus = .granted
        } else {
            screenRecordingStatus = .denied
        }
    }

    /// Request screen recording permission using a 3-step approach (adapted from Snapzy):
    /// 1. Fast-path if already granted via CGPreflightScreenCaptureAccess
    /// 2. Try SCShareableContent.current — auto-adds app on macOS 13-14
    /// 3. Fallback: CGRequestScreenCaptureAccess → opens System Settings (macOS 15+)
    func requestScreenRecording() async {
        // Step 1: Fast path — already granted
        if CGPreflightScreenCaptureAccess() {
            screenRecordingStatus = .granted
            return
        }

        // Step 2: Try SCShareableContent — triggers native permission dialog
        // on macOS 13-14 that auto-adds the app to Screen Recording list.
        do {
            _ = try await SCShareableContent.current
            // If we reach here, the system granted access
            screenRecordingStatus = .granted
            return
        } catch {
            // SCShareableContent threw — permission not yet granted
        }

        // Step 3: Fallback — CGRequestScreenCaptureAccess
        // On macOS 15+, this opens System Settings
        let granted = CGRequestScreenCaptureAccess()
        if granted {
            screenRecordingStatus = .granted
        } else {
            openScreenRecordingPreferences()
            screenRecordingStatus = .denied
        }
    }

    /// Open System Settings to the Screen Recording privacy pane
    func openScreenRecordingPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Gate for capture methods — throws if permission is not granted.
    /// Uses CGPreflightScreenCaptureAccess which is lightweight and never shows UI.
    func ensureScreenRecordingPermission() throws {
        guard CGPreflightScreenCaptureAccess() else {
            screenRecordingStatus = .denied
            throw PermissionError.screenRecordingDenied
        }
        screenRecordingStatus = .granted
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

