import Testing
import CoreGraphics
@testable import SnapForge

/// Tests for CaptureSessionManager — mode routing and overlay management
@MainActor
struct CaptureSessionManagerTests {

    @Test func sharedInstanceIsSingleton() {
        let a = CaptureSessionManager.shared
        let b = CaptureSessionManager.shared
        #expect(a === b, "Should be the same singleton instance")
    }

    @Test func dismissOverlayWhenNoneDoesNotCrash() {
        CaptureSessionManager.shared.dismissOverlay()
        // Test passes if no crash
    }
}

/// Tests for SCKitService — capture types and availability
@MainActor
struct SCKitServiceTests {

    @Test func windowInfoInitiallyEmpty() {
        let service = SCKitService()
        #expect(service.availableWindows.isEmpty, "Windows should be empty before refresh")
    }

    @Test func refreshContentDoesNotThrow() async throws {
        let service = SCKitService()
        await withKnownIssue("Fails in CI without screen recording permission") {
            try await service.refreshContent()
            #expect(service.availableDisplays.isEmpty == false, "Should have at least one display")
        }
    }

    @Test func captureFullscreenProducesImage() async throws {
        let service = SCKitService()
        await withKnownIssue("Fails in CI without screen recording permission") {
            let image = try await service.captureFullscreen()
            #expect(image.size.width > 0)
            #expect(image.size.height > 0)
        }
    }

    @Test func captureAreaProducesImage() async throws {
        let service = SCKitService()
        let rect = CGRect(x: 100, y: 100, width: 200, height: 200)
        await withKnownIssue("Fails in CI without screen recording permission") {
            let image = try await service.captureArea(rect)
            #expect(image.size.width > 0)
            #expect(image.size.height > 0)
        }
    }
}
