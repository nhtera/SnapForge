import Testing
import CoreGraphics
import ScreenCaptureKit
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

    /// Attempts to fetch shareable content. Returns nil when screen recording
    /// permission is unavailable (CI), recording the absence as a known issue.
    private static func fetchContentIfPermitted() async -> SCShareableContent? {
        do {
            return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            withKnownIssue("Screen recording permission not granted — skipping") {
                throw error
            }
            return nil
        }
    }

    @Test func windowInfoInitiallyEmpty() {
        let service = SCKitService()
        #expect(service.availableWindows.isEmpty, "Windows should be empty before refresh")
    }

    @Test func refreshContentDoesNotThrow() async throws {
        guard await Self.fetchContentIfPermitted() != nil else { return }
        let service = SCKitService()
        try await service.refreshContent()
        #expect(service.availableDisplays.isEmpty == false, "Should have at least one display")
    }

    @Test func captureFullscreenProducesImage() async throws {
        guard await Self.fetchContentIfPermitted() != nil else { return }
        let service = SCKitService()
        let image = try await service.captureFullscreen()
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }

    @Test func captureAreaProducesImage() async throws {
        guard await Self.fetchContentIfPermitted() != nil else { return }
        let service = SCKitService()
        let rect = CGRect(x: 100, y: 100, width: 200, height: 200)
        let image = try await service.captureArea(rect)
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }
}
