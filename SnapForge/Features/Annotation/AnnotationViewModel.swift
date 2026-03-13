import SwiftUI

/// ViewModel for the annotation editor.
@Observable
final class AnnotationViewModel {
    var selectedTool: AnnotationType = .select
    var selectedColor: Color = .red
    var strokeWidth: CGFloat = 3
    var opacity: Double = 1.0

    private var undoStack: [[any AnnotationItem]] = []
    private var redoStack: [[any AnnotationItem]] = []
    var annotations: [any AnnotationItem] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Undo/Redo

    func undo() {
        guard !undoStack.isEmpty else { return }
        redoStack.append(annotations)
        annotations = undoStack.removeLast()
    }

    func redo() {
        guard !redoStack.isEmpty else { return }
        undoStack.append(annotations)
        annotations = redoStack.removeLast()
    }

    func saveState() {
        undoStack.append(annotations)
        redoStack.removeAll()
    }

    // MARK: - Annotation Operations

    func addAnnotation(_ item: any AnnotationItem) {
        saveState()
        annotations.append(item)
    }

    func removeAnnotation(id: UUID) {
        saveState()
        annotations.removeAll { $0.id == id }
    }

    func clearAll() {
        saveState()
        annotations.removeAll()
    }
}
