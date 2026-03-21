import SwiftUI

/// Observable state for recording annotations with auto-clear support
@MainActor @Observable
final class RecordingAnnotationState {
    var annotations: [RecordingAnnotationEntry] = []
    var selectedTool: AnnotationToolType = .selection
    var selectedAnnotationId: UUID?
    var strokeColor: Color = .red
    var strokeWidth: CGFloat = 3
    var isAnnotationEnabled: Bool = false
    var toolClearModes: [AnnotationToolType: RecordingAnnotationClearMode] = [:]
    /// Whether modifier-hold shortcut mode is active
    var isShortcutModeActive: Bool = false
    /// Auto-incrementing counter for counter tool
    var nextCounterValue: Int = 1
    /// Font size for text annotations
    var selectedFontSize: CGFloat = 20
    /// Blur style for blur redaction tool
    var selectedBlurType: BlurType = .pixelated

    /// Weak ref to canvas for triggering redraws
    weak var canvasView: RecordingAnnotationCanvasView?

    private var cleanupTimer: Timer?

    // MARK: - Undo/Redo

    /// Action-based undo: tracks both add and delete operations
    enum UndoAction {
        case added(RecordingAnnotationEntry)   // was added → undo removes it
        case deleted(RecordingAnnotationEntry)  // was deleted → undo restores it
    }

    private static let maxUndoDepth = 50
    private var undoStack: [UndoAction] = []
    private var redoStack: [UndoAction] = []
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Tools available during recording (subset of all annotation tools)
    static let availableTools: [AnnotationToolType] = [
        .selection, .rectangle, .oval, .arrow, .line, .pencil, .highlighter,
        .text, .counter, .blur, .spotlight, .laserPointer,
    ]

    /// Laser pointer state for ephemeral cursor trail
    let laserPointerState = RecordingLaserPointerState()

    // MARK: - Mutation

    func appendAnnotation(_ item: AnnotationItem, tool: AnnotationToolType) {
        let entry = RecordingAnnotationEntry(item: item, tool: tool)
        annotations.append(entry)
        undoStack.append(.added(entry))
        redoStack.removeAll()
        trimUndoStack()
        enforceCountLimit(for: tool)
        canvasView?.refresh()
    }

    func clearAll() {
        annotations.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()
        selectedAnnotationId = nil
        nextCounterValue = 1
        canvasView?.refresh()
    }

    func deleteSelected() {
        guard let id = selectedAnnotationId,
              let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        let removed = annotations.remove(at: idx)
        undoStack.append(.deleted(removed))
        redoStack.removeAll()
        trimUndoStack()
        selectedAnnotationId = nil
        canvasView?.refresh()
    }

    func undo() {
        guard let action = undoStack.popLast() else { return }
        switch action {
        case .added(let entry):
            // Was added → remove it
            annotations.removeAll { $0.id == entry.id }
            redoStack.append(.added(entry))
        case .deleted(let entry):
            // Was deleted → restore it
            annotations.append(entry)
            redoStack.append(.deleted(entry))
        }
        selectedAnnotationId = nil
        canvasView?.refresh()
    }

    func redo() {
        guard let action = redoStack.popLast() else { return }
        switch action {
        case .added(let entry):
            // Was added → re-add it
            annotations.append(entry)
            undoStack.append(.added(entry))
        case .deleted(let entry):
            // Was deleted → re-delete it
            annotations.removeAll { $0.id == entry.id }
            undoStack.append(.deleted(entry))
        }
        canvasView?.refresh()
    }

    private func trimUndoStack() {
        while undoStack.count > Self.maxUndoDepth {
            undoStack.removeFirst()
        }
    }

    func clearMode(for tool: AnnotationToolType) -> RecordingAnnotationClearMode {
        toolClearModes[tool] ?? .persist
    }

    // MARK: - Cleanup Timer

    func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.removeExpired() }
        }
    }

    func stopCleanupTimer() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }

    // MARK: - Private

    private func removeExpired() {
        let now = Date()
        var changed = false

        for i in (0..<annotations.count).reversed() {
            let entry = annotations[i]
            let mode = clearMode(for: entry.createdByTool)
            guard case .timeBased(let seconds) = mode else { continue }

            let age = now.timeIntervalSince(entry.createdAt)
            if age > seconds {
                // Fade out over 0.3s
                let fadeProgress = min(1.0, (age - seconds) / 0.3)
                if fadeProgress >= 1.0 {
                    annotations.remove(at: i)
                    changed = true
                } else {
                    annotations[i].opacity = 1.0 - fadeProgress
                    changed = true
                }
            }
        }

        if changed { canvasView?.refresh() }
    }

    private func enforceCountLimit(for tool: AnnotationToolType) {
        guard case .countBased(let limit) = clearMode(for: tool) else { return }
        let toolEntries = annotations.filter { $0.createdByTool == tool }
        if toolEntries.count > limit {
            let excess = toolEntries.count - limit
            let idsToRemove = toolEntries.prefix(excess).map(\.id)
            annotations.removeAll { idsToRemove.contains($0.id) }
        }
    }
}
