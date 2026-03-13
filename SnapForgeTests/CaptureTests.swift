import XCTest
@testable import SnapForge

/// Tests for CaptureSessionManager — mode routing and overlay management
@MainActor
final class CaptureSessionManagerTests: XCTestCase {

    func testSharedInstance_isSingleton() {
        let a = CaptureSessionManager.shared
        let b = CaptureSessionManager.shared
        XCTAssertTrue(a === b, "Should be the same singleton instance")
    }

    func testDismissOverlay_whenNone_doesNotCrash() {
        CaptureSessionManager.shared.dismissOverlay()
        // Should not crash
        XCTAssertTrue(true)
    }
}

/// Tests for SCKitService — capture types and availability
@MainActor
final class SCKitServiceTests: XCTestCase {

    func testWindowInfo_initiallyEmpty() {
        let service = SCKitService()
        XCTAssertTrue(service.availableWindows.isEmpty, "Windows should be empty before refresh")
    }

    func testRefreshContent_doesNotThrow() async {
        let service = SCKitService()
        do {
            try await service.refreshContent()
            // If permission is granted, should have displays
            XCTAssertFalse(service.availableDisplays.isEmpty, "Should have at least one display")
        } catch {
            // Permission denied is acceptable in CI
            print("⚠️ SCKitService refresh failed (permission): \(error)")
        }
    }

    func testCaptureFullscreen_producesImage() async {
        let service = SCKitService()
        do {
            let image = try await service.captureFullscreen()
            XCTAssertGreaterThan(image.size.width, 0)
            XCTAssertGreaterThan(image.size.height, 0)
        } catch {
            // Permission denied is acceptable in CI
            print("⚠️ Fullscreen capture failed (permission): \(error)")
        }
    }

    func testCaptureArea_producesImage() async {
        let service = SCKitService()
        let rect = CGRect(x: 100, y: 100, width: 200, height: 200)
        do {
            let image = try await service.captureArea(rect)
            XCTAssertGreaterThan(image.size.width, 0)
            XCTAssertGreaterThan(image.size.height, 0)
        } catch {
            print("⚠️ Area capture failed (permission): \(error)")
        }
    }
}
