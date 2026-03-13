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

    /// Probes screen recording permission by attempting to fetch shareable content.
    /// Returns nil if permission is not granted (test should skip).
    private static func requireScreenRecordingPermission() async throws -> SCShareableContent {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            try #require(Bool(false), "Skipping: screen recording permission not granted")
            fatalError("Unreachable")
        }
        return content
    }

    @Test func windowInfoInitiallyEmpty() {
        let service = SCKitService()
        #expect(service.availableWindows.isEmpty, "Windows should be empty before refresh")
    }

    @Test func refreshContentDoesNotThrow() async throws {
        _ = try await Self.requireScreenRecordingPermission()
        let service = SCKitService()
        try await service.refreshContent()
        #expect(service.availableDisplays.isEmpty == false, "Should have at least one display")
    }

    @Test func captureFullscreenProducesImage() async throws {
        _ = try await Self.requireScreenRecordingPermission()
        let service = SCKitService()
        let image = try await service.captureFullscreen()
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }

    @Test func captureAreaProducesImage() async throws {
        _ = try await Self.requireScreenRecordingPermission()
        let service = SCKitService()
        let rect = CGRect(x: 100, y: 100, width: 200, height: 200)
        let image = try await service.captureArea(rect)
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }
}
