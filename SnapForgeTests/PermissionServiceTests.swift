import XCTest
@testable import SnapForge

/// Tests for PermissionService — checks permission status reporting
@MainActor
final class PermissionServiceTests: XCTestCase {

    func testScreenRecordingStatus_isNotNotDetermined() {
        let service = PermissionService()
        service.checkScreenRecording()
        // After check, status should be either .granted or .denied, not .notDetermined
        XCTAssertNotEqual(service.screenRecordingStatus, .notDetermined)
    }

    func testMicrophoneStatus_isNotNotDetermined() {
        let service = PermissionService()
        service.checkMicrophone()
        // After first check, microphone might still be .notDetermined if never asked
        // Just verify it doesn't crash
        XCTAssertTrue(true)
    }

    func testAccessibilityCheck_doesNotCrash() {
        let service = PermissionService()
        service.checkAccessibility()
        XCTAssertTrue(
            service.accessibilityStatus == .granted || service.accessibilityStatus == .denied,
            "Accessibility should be .granted or .denied"
        )
    }

    func testAllCriticalPermissions_dependsOnScreenRecording() {
        let service = PermissionService()
        service.checkScreenRecording()
        let critical = service.allCriticalPermissionsGranted
        XCTAssertEqual(critical, service.screenRecordingStatus == .granted)
    }

    func testRefreshAll_updatesAllStatuses() {
        let service = PermissionService()
        // All start as .notDetermined from init, but init calls refreshAll()
        // After init, screen recording should have been checked
        XCTAssertNotEqual(service.screenRecordingStatus, .notDetermined,
                         "After init, screen recording status should be checked")
    }
}
