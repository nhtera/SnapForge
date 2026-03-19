import AppKit

/// Provides magnetic snap-to guides when dragging/resizing the recording region.
/// Snaps to: window edges, screen halves/thirds, and common resolutions.
@MainActor
final class RecordingRegionSnapService {
    struct SnapResult {
        var adjustedRect: CGRect
        var guideLines: [SnapGuideLine]
    }

    struct SnapGuideLine: Equatable {
        enum Orientation: Equatable { case horizontal, vertical }
        let orientation: Orientation
        let position: CGFloat
    }

    private let threshold: CGFloat = 10
    private var windowFrames: [CGRect] = []
    private var screenFrame: CGRect = .zero

    /// Call once at drag/resize start to cache window positions
    func beginDragSession() {
        screenFrame = NSScreen.main?.visibleFrame ?? .zero
        windowFrames = fetchVisibleWindowFrames()
    }

    /// Compute snapped rect from proposed rect
    func snap(proposedRect: CGRect, isResizing: Bool) -> SnapResult {
        let enabled = UserDefaults.standard.object(forKey: SettingsKey.regionSnappingEnabled) as? Bool ?? true
        guard enabled, !NSEvent.modifierFlags.contains(.option) else {
            return SnapResult(adjustedRect: proposedRect, guideLines: [])
        }

        var rect = proposedRect
        var guides: [SnapGuideLine] = []

        if isResizing { snapToResolutions(&rect, &guides) }
        snapToEdges(&rect, &guides, isResizing: isResizing)
        snapToScreenDivisions(&rect, &guides)

        return SnapResult(adjustedRect: rect, guideLines: guides)
    }

    // MARK: - Private

    private func snapToEdges(_ rect: inout CGRect, _ guides: inout [SnapGuideLine], isResizing: Bool) {
        var allEdgesX: [CGFloat] = [screenFrame.minX, screenFrame.maxX]
        var allEdgesY: [CGFloat] = [screenFrame.minY, screenFrame.maxY]
        for w in windowFrames {
            allEdgesX.append(contentsOf: [w.minX, w.maxX])
            allEdgesY.append(contentsOf: [w.minY, w.maxY])
        }

        // Snap left/right edges
        for targetX in allEdgesX {
            if abs(rect.minX - targetX) < threshold {
                if isResizing { rect.size.width += rect.origin.x - targetX }
                rect.origin.x = targetX
                guides.append(.init(orientation: .vertical, position: targetX))
            } else if abs(rect.maxX - targetX) < threshold {
                if isResizing { rect.size.width = targetX - rect.origin.x }
                else { rect.origin.x = targetX - rect.width }
                guides.append(.init(orientation: .vertical, position: targetX))
            }
        }

        // Snap top/bottom edges
        for targetY in allEdgesY {
            if abs(rect.minY - targetY) < threshold {
                if isResizing { rect.size.height += rect.origin.y - targetY }
                rect.origin.y = targetY
                guides.append(.init(orientation: .horizontal, position: targetY))
            } else if abs(rect.maxY - targetY) < threshold {
                if isResizing { rect.size.height = targetY - rect.origin.y }
                else { rect.origin.y = targetY - rect.height }
                guides.append(.init(orientation: .horizontal, position: targetY))
            }
        }
    }

    private func snapToScreenDivisions(_ rect: inout CGRect, _ guides: inout [SnapGuideLine]) {
        let sf = screenFrame
        let divX = [sf.minX + sf.width / 3, sf.midX, sf.minX + sf.width * 2 / 3]
        let divY = [sf.minY + sf.height / 3, sf.midY, sf.minY + sf.height * 2 / 3]

        for x in divX where abs(rect.midX - x) < threshold {
            rect.origin.x = x - rect.width / 2
            guides.append(.init(orientation: .vertical, position: x))
        }
        for y in divY where abs(rect.midY - y) < threshold {
            rect.origin.y = y - rect.height / 2
            guides.append(.init(orientation: .horizontal, position: y))
        }
    }

    private func snapToResolutions(_ rect: inout CGRect, _ guides: inout [SnapGuideLine]) {
        let commonSizes: [CGSize] = [
            CGSize(width: 1920, height: 1080),
            CGSize(width: 1280, height: 720),
            CGSize(width: 854, height: 480),
            CGSize(width: 640, height: 480),
        ]
        for size in commonSizes {
            if abs(rect.width - size.width) < threshold && abs(rect.height - size.height) < threshold {
                rect.size = size
                break
            }
        }
    }

    private func fetchVisibleWindowFrames() -> [CGRect] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        let screenH = NSScreen.main?.frame.height ?? 0
        let myPID = ProcessInfo.processInfo.processIdentifier

        return list.compactMap { info -> CGRect? in
            guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let w = bounds["Width"], let h = bounds["Height"],
                  let ownerPID = info[kCGWindowOwnerPID as String] as? Int,
                  ownerPID != Int(myPID), w > 50, h > 50 else { return nil }
            // Convert CG top-left to Cocoa bottom-left
            return CGRect(x: x, y: screenH - y - h, width: w, height: h)
        }
    }
}
