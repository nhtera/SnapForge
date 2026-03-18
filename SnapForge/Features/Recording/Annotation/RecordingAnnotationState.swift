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

    /// Weak ref to canvas for triggering redraws
    weak var canvasView: RecordingAnnotationCanvasView?

    private var cleanupTimer: Timer?

    /// Tools available during recording (subset of all annotation tools)
    static let availableTools: [AnnotationToolType] = [
        .selection, .rectangle, .oval, .arrow, .line, .pencil, .highlighter,
    ]

    // MARK: - Mutation

    func appendAnnotation(_ item: AnnotationItem, tool: AnnotationToolType) {
        let entry = RecordingAnnotationEntry(item: item, tool: tool)
        annotations.append(entry)
        enforceCountLimit(for: tool)
        canvasView?.refresh()
    }

    func clearAll() {
        annotations.removeAll()
        selectedAnnotationId = nil
        canvasView?.refresh()
    }

    func deleteSelected() {
        guard let id = selectedAnnotationId else { return }
        annotations.removeAll { $0.id == id }
        selectedAnnotationId = nil
        canvasView?.refresh()
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
