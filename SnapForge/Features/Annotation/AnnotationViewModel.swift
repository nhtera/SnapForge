import SwiftUI

/// ViewModel for the annotation editor.
@Observable
final class AnnotationViewModel {
    var selectedTool: AnnotationType = .select
    var selectedColor: Color = .red
    var strokeWidth: CGFloat = 3
    var opacity: Double = 1.0
    var fillShape: Bool = false
    var cursorPosition: CGPoint = .zero
    var cropRect: CGRect?

    private var undoStack: [[any AnnotationItem]] = []
    private var redoStack: [[any AnnotationItem]] = []
    var annotations: [any AnnotationItem] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private var counterValue: Int = 0

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
        guard !annotations.isEmpty else { return }
        saveState()
        annotations.removeAll()
        counterValue = 0
    }

    // MARK: - Counter

    func nextCounterNumber() -> Int {
        counterValue += 1
        return counterValue
    }

    // MARK: - Text Update

    func updateText(id: UUID, newText: String) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        guard var textItem = annotations[index] as? TextAnnotation else { return }
        saveState()
        textItem.text = newText
        annotations[index] = textItem
    }

    // MARK: - Selection

    func selectAnnotation(at point: CGPoint) {
        // Deselect all first
        for i in annotations.indices {
            annotations[i].isSelected = false
        }

        // Find and select the topmost annotation containing the point
        for i in annotations.indices.reversed() {
            if hitTest(annotations[i], point: point) {
                annotations[i].isSelected = true
                break
            }
        }
    }

    private func hitTest(_ item: any AnnotationItem, point: CGPoint) -> Bool {
        let margin: CGFloat = 8

        if let shape = item as? ShapeAnnotation {
            return shape.rect.insetBy(dx: -margin, dy: -margin).contains(point)
        } else if let arrow = item as? ArrowAnnotation {
            return distanceFromPointToLine(point: point,
                                           lineStart: arrow.startPoint,
                                           lineEnd: arrow.endPoint) < margin * 2
        } else if let text = item as? TextAnnotation {
            let textRect = CGRect(x: text.position.x - margin,
                                  y: text.position.y - margin,
                                  width: 200 + margin * 2,
                                  height: 30 + margin * 2)
            return textRect.contains(point)
        } else if let counter = item as? CounterAnnotation {
            let dx = point.x - counter.position.x
            let dy = point.y - counter.position.y
            return sqrt(dx * dx + dy * dy) < counter.size
        } else if let pencil = item as? PencilAnnotation {
            return pencil.points.contains { p in
                let dx = point.x - p.x
                let dy = point.y - p.y
                return sqrt(dx * dx + dy * dy) < margin * 2
            }
        } else if let effect = item as? EffectAnnotation {
            return effect.rect.insetBy(dx: -margin, dy: -margin).contains(point)
        }

        return false
    }

    private func distanceFromPointToLine(point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> CGFloat {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let lengthSquared = dx * dx + dy * dy

        if lengthSquared == 0 {
            return sqrt(pow(point.x - lineStart.x, 2) + pow(point.y - lineStart.y, 2))
        }

        var t = ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / lengthSquared
        t = max(0, min(1, t))

        let projX = lineStart.x + t * dx
        let projY = lineStart.y + t * dy

        return sqrt(pow(point.x - projX, 2) + pow(point.y - projY, 2))
    }
}
