import Foundation
import ScreenCaptureKit
import AppKit

/// Central ScreenCaptureKit service — enumerates displays, windows, and apps.
/// Wraps SCShareableContent with caching and error handling.
@MainActor
@Observable
final class SCKitService {

    struct CaptureableWindow: Identifiable, Hashable {
        let id: CGWindowID
        let title: String?
        let appName: String?
        let appBundleID: String?
        let frame: CGRect
        let isOnScreen: Bool
        let scWindow: SCWindow

        static func == (lhs: CaptureableWindow, rhs: CaptureableWindow) -> Bool {
            lhs.id == rhs.id
        }
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    struct CaptureableDisplay: Identifiable {
        let id: CGDirectDisplayID
        let width: Int
        let height: Int
        let scDisplay: SCDisplay
    }

    // MARK: - State

    var availableDisplays: [CaptureableDisplay] = []
    var availableWindows: [CaptureableWindow] = []
    var isLoading = false

    /// Excluded bundle IDs (don't show our own app in the window list)
    private let excludedBundleIDs: Set<String> = [
        "com.snapforge.app",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui"
    ]

    // MARK: - Content Enumeration

    /// Refresh the list of available displays and windows.
    func refreshContent() async throws {
        isLoading = true
        defer { isLoading = false }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        availableDisplays = content.displays.map { display in
            CaptureableDisplay(
                id: display.displayID,
                width: display.width,
                height: display.height,
                scDisplay: display
            )
        }

        availableWindows = content.windows
            .filter { window in
                // Filter out very small windows, unnamed windows, and excluded apps
                guard let app = window.owningApplication else { return false }
                guard !excludedBundleIDs.contains(app.bundleIdentifier) else { return false }
                guard window.frame.width > 50 && window.frame.height > 50 else { return false }
                return true
            }
            .map { window in
                CaptureableWindow(
                    id: window.windowID,
                    title: window.title,
                    appName: window.owningApplication?.applicationName,
                    appBundleID: window.owningApplication?.bundleIdentifier,
                    frame: window.frame,
                    isOnScreen: window.isOnScreen,
                    scWindow: window
                )
            }
    }

    // MARK: - Capture Operations

    /// Capture a specific area of the screen.
    func captureArea(_ rect: CGRect, display: SCDisplay? = nil) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let targetDisplay = display ?? content.displays.first!

        let filter = SCContentFilter(display: targetDisplay, excludingWindows: [])
        let config = SCStreamConfiguration()

        let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
        config.sourceRect = rect
        config.width = Int(rect.width * scaleFactor)
        config.height = Int(rect.height * scaleFactor)
        config.showsCursor = false
        config.captureResolution = .best

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        return NSImage(cgImage: cgImage, size: NSSize(width: rect.width, height: rect.height))
    }

    /// Capture the entire screen (fullscreen).
    func captureFullscreen(display: SCDisplay? = nil) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let targetDisplay = display ?? content.displays.first!

        let filter = SCContentFilter(display: targetDisplay, excludingWindows: [])
        let config = SCStreamConfiguration()

        let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
        config.width = Int(CGFloat(targetDisplay.width) * scaleFactor)
        config.height = Int(CGFloat(targetDisplay.height) * scaleFactor)
        config.showsCursor = false
        config.captureResolution = .best

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: targetDisplay.width, height: targetDisplay.height)
        )
    }

    /// Capture a specific window.
    func captureWindow(_ window: SCWindow) async throws -> NSImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()

        let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
        config.width = Int(window.frame.width * scaleFactor)
        config.height = Int(window.frame.height * scaleFactor)
        config.showsCursor = false
        config.captureResolution = .best
        config.shouldBeOpaque = false // Preserve window transparency/rounded corners

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: window.frame.width, height: window.frame.height)
        )
    }

    /// Capture a frozen frame of the entire screen (for freeze-screen effect).
    func captureFreezeFrame() async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw CaptureError.noDisplayFound
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()

        let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
        config.width = Int(CGFloat(display.width) * scaleFactor)
        config.height = Int(CGFloat(display.height) * scaleFactor)
        config.showsCursor = true
        config.captureResolution = .best

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: display.width, height: display.height)
        )
    }
}

// MARK: - Errors

enum CaptureError: LocalizedError {
    case noDisplayFound
    case noWindowSelected
    case permissionDenied
    case captureOperationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDisplayFound:
            return "No display found for capture."
        case .noWindowSelected:
            return "No window selected for capture."
        case .permissionDenied:
            return "Screen recording permission is required."
        case .captureOperationFailed(let detail):
            return "Capture failed: \(detail)"
        }
    }
}
