import SwiftUI
import AppKit

// MARK: - FileDragSource

/// An AppKit-backed drag handle that initiates a proper NSDraggingSession.
/// Works correctly inside panels with `isMovableByWindowBackground = true`
/// because `mouseDownCanMoveWindow` returns `false` for this view.
struct FileDragSource: NSViewRepresentable {
    let pasteboardWriter: NSPasteboardWriting
    let dragImage: NSImage
    let onDragEnded: (@Sendable (Bool) -> Void)?

    /// Create a drag source for a file URL.
    init(
        fileURL: URL,
        dragImage: NSImage,
        onDragEnded: (@Sendable (Bool) -> Void)? = nil
    ) {
        self.pasteboardWriter = fileURL as NSURL
        self.dragImage = dragImage
        self.onDragEnded = onDragEnded
    }

    /// Create a drag source for an NSImage (written as PNG data on the pasteboard).
    init(
        image: NSImage,
        onDragEnded: (@Sendable (Bool) -> Void)? = nil
    ) {
        self.pasteboardWriter = image
        self.dragImage = image
        self.onDragEnded = onDragEnded
    }

    func makeNSView(context: Context) -> DragSourceNSView {
        let view = DragSourceNSView()
        view.pasteboardWriter = pasteboardWriter
        view.dragImage = dragImage
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ nsView: DragSourceNSView, context: Context) {
        nsView.pasteboardWriter = pasteboardWriter
        nsView.dragImage = dragImage
        nsView.onDragEnded = onDragEnded
    }
}

// MARK: - DragSourceNSView

/// Custom NSView that starts a native NSDraggingSession on mouse drag.
/// `mouseDownCanMoveWindow = false` prevents `isMovableByWindowBackground` from stealing drag events.
final class DragSourceNSView: NSView {
    var pasteboardWriter: NSPasteboardWriting?
    var dragImage: NSImage?
    var onDragEnded: (@Sendable (Bool) -> Void)?

    private var mouseDownLocation: NSPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not implemented")
    }

    // Prevent isMovableByWindowBackground from stealing drags
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startLocation = mouseDownLocation else { return }

        let currentLocation = event.locationInWindow
        let dx = abs(currentLocation.x - startLocation.x)
        let dy = abs(currentLocation.y - startLocation.y)

        // Require minimum drag distance to avoid accidental triggers
        guard dx > 4 || dy > 4 else { return }

        // Reset to prevent re-triggering
        mouseDownLocation = nil

        guard let writer = pasteboardWriter else { return }

        // Create drag source with a retained reference
        let source = FileDragSessionSource(
            dragID: UUID(),
            onEnded: onDragEnded
        )
        FileDragRegistry.retain(source, for: source.dragID)

        let dragItem = NSDraggingItem(pasteboardWriter: writer)

        // Build drag image from thumbnail
        let imageSize = NSSize(width: 100, height: 62)
        let scaledImage = NSImage(size: imageSize)
        scaledImage.lockFocus()
        dragImage?.draw(
            in: NSRect(origin: .zero, size: imageSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 0.8
        )
        scaledImage.unlockFocus()

        dragItem.setDraggingFrame(
            NSRect(
                x: event.locationInWindow.x - imageSize.width / 2,
                y: event.locationInWindow.y - imageSize.height / 2,
                width: imageSize.width,
                height: imageSize.height
            ),
            contents: scaledImage
        )

        let session = beginDraggingSession(with: [dragItem], event: event, source: source)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownLocation = nil
    }
}

// MARK: - FileDragSessionSource

/// NSDraggingSource that handles drag session callbacks and retains itself via the registry.
private final class FileDragSessionSource: NSObject, NSDraggingSource {
    let dragID: UUID
    private let onEnded: (@Sendable (Bool) -> Void)?

    init(dragID: UUID, onEnded: (@Sendable (Bool) -> Void)?) {
        self.dragID = dragID
        self.onEnded = onEnded
        super.init()
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .outsideApplication ? .copy : .copy
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        let success = operation != []
        onEnded?(success)
        FileDragRegistry.release(for: dragID)
    }
}

// MARK: - FileDragRegistry

/// Retains drag source objects during the async drag session to prevent deallocation.
private enum FileDragRegistry {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var activeSources: [UUID: FileDragSessionSource] = [:]

    static func retain(_ source: FileDragSessionSource, for id: UUID) {
        lock.lock()
        activeSources[id] = source
        lock.unlock()
    }

    static func release(for id: UUID) {
        lock.lock()
        activeSources[id] = nil
        lock.unlock()
    }
}
