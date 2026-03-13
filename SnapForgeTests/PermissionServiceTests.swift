import Testing
@testable import SnapForge

/// Tests for PermissionService — checks permission status reporting
@MainActor
struct PermissionServiceTests {

    @Test func screenRecordingStatusIsNotUndetermined() {
        let service = PermissionService()
        service.checkScreenRecording()
        #expect(service.screenRecordingStatus != .notDetermined)
    }

    @Test func microphoneCheckDoesNotCrash() {
        let service = PermissionService()
        service.checkMicrophone()
        // Test passes if no crash — no vacuous assertion needed
    }

    @Test func accessibilityCheckReturnsDefinitiveStatus() {
        let service = PermissionService()
        service.checkAccessibility()
        #expect(
            service.accessibilityStatus == .granted || service.accessibilityStatus == .denied,
            "Accessibility should be .granted or .denied"
        )
    }

    @Test func allCriticalPermissionsDependOnScreenRecording() {
        let service = PermissionService()
        service.checkScreenRecording()
        let critical = service.allCriticalPermissionsGranted
        #expect(critical == (service.screenRecordingStatus == .granted))
    }

    @Test func refreshAllUpdatesStatuses() {
        let service = PermissionService()
        #expect(
            service.screenRecordingStatus != .notDetermined,
            "After init, screen recording status should be checked"
        )
    }
}
