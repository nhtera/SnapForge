import Testing
import SwiftUI
import AppKit
@testable import SnapForge

/// Comprehensive tests for all annotation tools and the annotation view model
@MainActor
struct AnnotationViewModelTests {

    private func makeVM() -> AnnotationViewModel {
        AnnotationViewModel()
    }

    // MARK: - Initial State

    @Test func initialState() {
        let vm = makeVM()
        #expect(vm.selectedTool == .select)
        #expect(vm.strokeWidth == 3)
        #expect(vm.opacity == 1.0)
        #expect(vm.fillShape == false)
        #expect(vm.annotations.isEmpty)
        #expect(vm.canUndo == false)
        #expect(vm.canRedo == false)
        #expect(vm.cropRect == nil)
    }

    // MARK: - Undo / Redo

    @Test func undoRestoresPreviousState() {
        let vm = makeVM()
        vm.addAnnotation(ShapeAnnotation(
            type: .rectangle,
            rect: CGRect(x: 0, y: 0, width: 100, height: 50),
            color: .red, strokeWidth: 2, isFilled: false, cornerRadius: 0
        ))
        #expect(vm.annotations.count == 1)
        #expect(vm.canUndo)

        vm.undo()
        #expect(vm.annotations.count == 0)
        #expect(vm.canRedo)
    }

    @Test func redoRestoresUndoneState() {
        let vm = makeVM()
        vm.addAnnotation(ShapeAnnotation(
            type: .ellipse,
            rect: CGRect(x: 10, y: 10, width: 80, height: 80),
            color: .blue, strokeWidth: 3, isFilled: true, cornerRadius: 0
        ))
        vm.undo()
        #expect(vm.annotations.count == 0)

        vm.redo()
        #expect(vm.annotations.count == 1)
        #expect(vm.canRedo == false)
    }

    @Test func addAnnotationClearsRedoStack() {
        let vm = makeVM()
        vm.addAnnotation(ShapeAnnotation(
            type: .rectangle, rect: .zero, color: .red,
            strokeWidth: 1, isFilled: false, cornerRadius: 0
        ))
        vm.undo()
        #expect(vm.canRedo)

        vm.addAnnotation(ShapeAnnotation(
            type: .ellipse, rect: .zero, color: .blue,
            strokeWidth: 1, isFilled: false, cornerRadius: 0
        ))
        #expect(vm.canRedo == false, "Adding new annotation should clear redo stack")
    }

    @Test func multipleUndoRedo() {
        let vm = makeVM()
        vm.addAnnotation(ShapeAnnotation(type: .rectangle, rect: .zero, color: .red, strokeWidth: 1, isFilled: false, cornerRadius: 0))
        vm.addAnnotation(ShapeAnnotation(type: .ellipse, rect: .zero, color: .blue, strokeWidth: 1, isFilled: false, cornerRadius: 0))
        vm.addAnnotation(ArrowAnnotation(startPoint: .zero, endPoint: CGPoint(x: 100, y: 100), color: .green, strokeWidth: 2, isCurved: false))

        #expect(vm.annotations.count == 3)

        vm.undo() // Back to 2
        #expect(vm.annotations.count == 2)

        vm.undo() // Back to 1
        #expect(vm.annotations.count == 1)

        vm.redo() // Forward to 2
        #expect(vm.annotations.count == 2)

        vm.undo() // Back to 1
        vm.undo() // Back to 0
        #expect(vm.annotations.count == 0)
        #expect(vm.canUndo == false)
    }

    @Test func undoWhenEmptyDoesNothing() {
        let vm = makeVM()
        vm.undo()
        #expect(vm.annotations.count == 0)
    }

    @Test func redoWhenEmptyDoesNothing() {
        let vm = makeVM()
        vm.redo()
        #expect(vm.annotations.count == 0)
    }

    // MARK: - Add Annotations

    @Test func addShapeAnnotationRectangle() throws {
        let vm = makeVM()
        let rect = CGRect(x: 50, y: 50, width: 200, height: 100)
        vm.addAnnotation(ShapeAnnotation(
            type: .rectangle, rect: rect, color: .red,
            strokeWidth: 3, isFilled: false, cornerRadius: 0
        ))

        #expect(vm.annotations.count == 1)
        let shape = try #require(vm.annotations[0] as? ShapeAnnotation)
        #expect(shape.type == .rectangle)
        #expect(shape.rect == rect)
        #expect(shape.isFilled == false)
    }

    @Test func addShapeAnnotationEllipse() throws {
        let vm = makeVM()
        vm.addAnnotation(ShapeAnnotation(
            type: .ellipse, rect: CGRect(x: 0, y: 0, width: 100, height: 100),
            color: .blue, strokeWidth: 2, isFilled: true, cornerRadius: 0
        ))

        let shape = try #require(vm.annotations[0] as? ShapeAnnotation)
        #expect(shape.type == .ellipse)
        #expect(shape.isFilled)
    }

    @Test func addArrowAnnotation() throws {
        let vm = makeVM()
        let start = CGPoint(x: 10, y: 20)
        let end = CGPoint(x: 200, y: 150)
        vm.addAnnotation(ArrowAnnotation(
            startPoint: start, endPoint: end,
            color: .red, strokeWidth: 2, isCurved: false
        ))

        let arrow = try #require(vm.annotations[0] as? ArrowAnnotation)
        #expect(arrow.type == .arrow)
        #expect(arrow.startPoint == start)
        #expect(arrow.endPoint == end)
        #expect(arrow.isCurved == false)
    }

    @Test func addArrowAnnotationAsLine() throws {
        let vm = makeVM()
        vm.addAnnotation(ArrowAnnotation(
            type: .line,
            startPoint: .zero, endPoint: CGPoint(x: 100, y: 0),
            color: .green, strokeWidth: 1, isCurved: false
        ))

        let line = try #require(vm.annotations[0] as? ArrowAnnotation)
        #expect(line.type == .line, "Line type should be .line, not .arrow")
    }

    @Test func addPencilAnnotation() throws {
        let vm = makeVM()
        let points: [CGPoint] = [
            CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 15),
            CGPoint(x: 30, y: 12), CGPoint(x: 40, y: 20), CGPoint(x: 50, y: 18)
        ]
        vm.addAnnotation(PencilAnnotation(
            points: points, color: .red, strokeWidth: 2, isSmoothed: true
        ))

        let pencil = try #require(vm.annotations[0] as? PencilAnnotation)
        #expect(pencil.points.count == 5)
        #expect(pencil.isSmoothed)
        #expect(pencil.type == .pencil)
    }

    @Test func addPencilAnnotationAsHighlighter() throws {
        let vm = makeVM()
        vm.addAnnotation(PencilAnnotation(
            type: .highlighter,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 200, y: 0)],
            color: .yellow.opacity(0.3), strokeWidth: 12, isSmoothed: false
        ))

        let highlighter = try #require(vm.annotations[0] as? PencilAnnotation)
        #expect(highlighter.type == .highlighter)
        #expect(highlighter.isSmoothed == false)
        #expect(highlighter.strokeWidth >= 12)
    }

    @Test func addTextAnnotation() throws {
        let vm = makeVM()
        vm.addAnnotation(TextAnnotation(
            position: CGPoint(x: 100, y: 100), text: "Hello World",
            font: .systemFont(ofSize: 16), color: .red, backgroundColor: nil, style: .plain
        ))

        let text = try #require(vm.annotations[0] as? TextAnnotation)
        #expect(text.text == "Hello World")
        #expect(text.style == .plain)
    }

    @Test func addTextAnnotationBoxedStyle() throws {
        let vm = makeVM()
        vm.addAnnotation(TextAnnotation(
            position: CGPoint(x: 50, y: 50), text: "Boxed",
            font: .systemFont(ofSize: 14), color: .blue, backgroundColor: .white, style: .boxed
        ))

        let text = try #require(vm.annotations[0] as? TextAnnotation)
        #expect(text.style == .boxed)
        #expect(text.backgroundColor != nil)
    }

    @Test func addCounterAnnotation() throws {
        let vm = makeVM()
        let num = vm.nextCounterNumber()
        vm.addAnnotation(CounterAnnotation(
            position: CGPoint(x: 200, y: 200), number: num, color: .red, size: 28
        ))

        let counter = try #require(vm.annotations[0] as? CounterAnnotation)
        #expect(counter.number == 1)
        #expect(counter.size == 28)
    }

    @Test func counterAutoIncrement() {
        let vm = makeVM()
        #expect(vm.nextCounterNumber() == 1)
        #expect(vm.nextCounterNumber() == 2)
        #expect(vm.nextCounterNumber() == 3)
    }

    @Test func counterResetsOnClearAll() {
        let vm = makeVM()
        _ = vm.nextCounterNumber()
        _ = vm.nextCounterNumber()
        vm.addAnnotation(CounterAnnotation(position: .zero, number: 2, color: .red, size: 28))
        vm.clearAll()
        #expect(vm.nextCounterNumber() == 1)
    }

    @Test func addEffectAnnotationBlur() throws {
        let vm = makeVM()
        vm.addAnnotation(EffectAnnotation(type: .blur, rect: CGRect(x: 50, y: 50, width: 100, height: 60), intensity: 0.8))

        let effect = try #require(vm.annotations[0] as? EffectAnnotation)
        #expect(effect.type == .blur)
        #expect(effect.intensity == 0.8)
    }

    @Test func addEffectAnnotationPixelate() throws {
        let vm = makeVM()
        vm.addAnnotation(EffectAnnotation(type: .pixelate, rect: CGRect(x: 0, y: 0, width: 100, height: 100), intensity: 0.5))

        let effect = try #require(vm.annotations[0] as? EffectAnnotation)
        #expect(effect.type == .pixelate)
    }

    @Test func addEffectAnnotationSpotlight() throws {
        let vm = makeVM()
        vm.addAnnotation(EffectAnnotation(type: .spotlight, rect: CGRect(x: 100, y: 100, width: 200, height: 200), intensity: 1.0))

        let effect = try #require(vm.annotations[0] as? EffectAnnotation)
        #expect(effect.type == .spotlight)
    }

    // MARK: - Remove Annotation

    @Test func removeAnnotationByID() {
        let vm = makeVM()
        let annotation = ShapeAnnotation(type: .rectangle, rect: .zero, color: .red, strokeWidth: 1, isFilled: false, cornerRadius: 0)
        vm.addAnnotation(annotation)
        #expect(vm.annotations.count == 1)

        vm.removeAnnotation(id: annotation.id)
        #expect(vm.annotations.count == 0)
    }

    @Test func removeAnnotationNonexistentIDDoesNothing() {
        let vm = makeVM()
        vm.addAnnotation(ShapeAnnotation(type: .rectangle, rect: .zero, color: .red, strokeWidth: 1, isFilled: false, cornerRadius: 0))
        vm.removeAnnotation(id: UUID())
        #expect(vm.annotations.count == 1)
    }

    // MARK: - Clear All

    @Test func clearAllRemovesAllAnnotations() {
        let vm = makeVM()
        vm.addAnnotation(ShapeAnnotation(type: .rectangle, rect: .zero, color: .red, strokeWidth: 1, isFilled: false, cornerRadius: 0))
        vm.addAnnotation(ArrowAnnotation(startPoint: .zero, endPoint: CGPoint(x: 100, y: 100), color: .blue, strokeWidth: 2, isCurved: false))
        vm.clearAll()
        #expect(vm.annotations.isEmpty)
        #expect(vm.canUndo, "Should be undoable")
    }

    @Test func clearAllWhenEmptyDoesNotAddUndoState() {
        let vm = makeVM()
        vm.clearAll()
        #expect(vm.canUndo == false, "Empty clearAll should not add undo state")
    }

    // MARK: - Text Update

    @Test func updateTextChangesTextContent() throws {
        let vm = makeVM()
        let textAnnotation = TextAnnotation(
            position: CGPoint(x: 100, y: 100), text: "Original",
            font: .systemFont(ofSize: 14), color: .red, backgroundColor: nil, style: .plain
        )
        vm.addAnnotation(textAnnotation)

        vm.updateText(id: textAnnotation.id, newText: "Updated Text")

        let updated = try #require(vm.annotations[0] as? TextAnnotation)
        #expect(updated.text == "Updated Text")
    }

    @Test func updateTextNonexistentIDDoesNothing() throws {
        let vm = makeVM()
        vm.addAnnotation(TextAnnotation(
            position: .zero, text: "Test", font: .systemFont(ofSize: 14),
            color: .red, backgroundColor: nil, style: .plain
        ))
        vm.updateText(id: UUID(), newText: "Nope")

        let text = try #require(vm.annotations[0] as? TextAnnotation)
        #expect(text.text == "Test")
    }

    @Test func updateTextOnNonTextAnnotationDoesNothing() {
        let vm = makeVM()
        let shape = ShapeAnnotation(type: .rectangle, rect: .zero, color: .red, strokeWidth: 1, isFilled: false, cornerRadius: 0)
        vm.addAnnotation(shape)
        vm.updateText(id: shape.id, newText: "Should not work")
        #expect(vm.annotations.count == 1)
    }

    // MARK: - Selection / Hit Testing

    @Test func selectAnnotationShape() {
        let vm = makeVM()
        let shape = ShapeAnnotation(
            type: .rectangle, rect: CGRect(x: 50, y: 50, width: 100, height: 100),
            color: .red, strokeWidth: 2, isFilled: false, cornerRadius: 0
        )
        vm.addAnnotation(shape)
        vm.selectAnnotation(at: CGPoint(x: 75, y: 75))
        #expect(vm.annotations[0].isSelected)
    }

    @Test func selectAnnotationMissedClickDeselectsAll() {
        let vm = makeVM()
        var shape = ShapeAnnotation(
            type: .rectangle, rect: CGRect(x: 50, y: 50, width: 100, height: 100),
            color: .red, strokeWidth: 2, isFilled: false, cornerRadius: 0
        )
        shape.isSelected = true
        vm.addAnnotation(shape)
        vm.selectAnnotation(at: CGPoint(x: 500, y: 500))
        #expect(vm.annotations[0].isSelected == false)
    }

    @Test func selectAnnotationArrow() {
        let vm = makeVM()
        vm.addAnnotation(ArrowAnnotation(
            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 100, y: 100),
            color: .red, strokeWidth: 2, isCurved: false
        ))
        vm.selectAnnotation(at: CGPoint(x: 50, y: 50))
        #expect(vm.annotations[0].isSelected)
    }

    @Test func selectAnnotationCounter() {
        let vm = makeVM()
        vm.addAnnotation(CounterAnnotation(position: CGPoint(x: 100, y: 100), number: 1, color: .red, size: 28))
        vm.selectAnnotation(at: CGPoint(x: 105, y: 105))
        #expect(vm.annotations[0].isSelected)
    }

    @Test func selectAnnotationTopmostWins() {
        let vm = makeVM()
        vm.addAnnotation(ShapeAnnotation(
            type: .rectangle, rect: CGRect(x: 0, y: 0, width: 200, height: 200),
            color: .red, strokeWidth: 1, isFilled: false, cornerRadius: 0
        ))
        vm.addAnnotation(ShapeAnnotation(
            type: .rectangle, rect: CGRect(x: 50, y: 50, width: 100, height: 100),
            color: .blue, strokeWidth: 1, isFilled: false, cornerRadius: 0
        ))
        vm.selectAnnotation(at: CGPoint(x: 75, y: 75))
        #expect(vm.annotations[0].isSelected == false, "Bottom shape should NOT be selected")
        #expect(vm.annotations[1].isSelected, "Top shape SHOULD be selected")
    }

    // MARK: - Crop Rect

    @Test func cropRectCanBeSet() {
        let vm = makeVM()
        let rect = CGRect(x: 10, y: 10, width: 200, height: 150)
        vm.cropRect = rect
        #expect(vm.cropRect == rect)
    }
}

// MARK: - Annotation Types Tests

struct AnnotationTypeTests {

    @Test(arguments: AnnotationType.allCases)
    func toolHasIconAndRawValue(tool: AnnotationType) {
        #expect(tool.icon.isEmpty == false, "\(tool.rawValue) should have an icon")
        #expect(tool.rawValue.isEmpty == false)
    }

    @Test func allCasesCount() {
        #expect(AnnotationType.allCases.count == 13)
    }

    @Test func identifiersAreUnique() {
        let ids = AnnotationType.allCases.map { $0.id }
        let uniqueIds = Set(ids)
        #expect(ids.count == uniqueIds.count, "All tool IDs should be unique")
    }
}

// MARK: - Annotation Item Model Tests

struct AnnotationItemModelTests {

    @Test func shapeAnnotationHasUniqueID() {
        let a = ShapeAnnotation(type: .rectangle, rect: .zero, color: .red, strokeWidth: 1, isFilled: false, cornerRadius: 0)
        let b = ShapeAnnotation(type: .rectangle, rect: .zero, color: .red, strokeWidth: 1, isFilled: false, cornerRadius: 0)
        #expect(a.id != b.id)
    }

    @Test func arrowAnnotationDefaultType() {
        let arrow = ArrowAnnotation(startPoint: .zero, endPoint: .zero, color: .red, strokeWidth: 1, isCurved: false)
        #expect(arrow.type == .arrow)
    }

    @Test func arrowAnnotationLineType() {
        let line = ArrowAnnotation(type: .line, startPoint: .zero, endPoint: .zero, color: .red, strokeWidth: 1, isCurved: false)
        #expect(line.type == .line)
    }

    @Test func pencilAnnotationDefaultType() {
        let pencil = PencilAnnotation(points: [], color: .red, strokeWidth: 1, isSmoothed: true)
        #expect(pencil.type == .pencil)
    }

    @Test func pencilAnnotationHighlighterType() {
        let hl = PencilAnnotation(type: .highlighter, points: [], color: .yellow, strokeWidth: 12, isSmoothed: false)
        #expect(hl.type == .highlighter)
    }

    @Test func textAnnotationAllStyles() {
        let styles = TextAnnotation.TextStyle.allCases
        #expect(styles.count == 7)
        #expect(styles.contains(.plain))
        #expect(styles.contains(.boxed))
        #expect(styles.contains(.callout))
        #expect(styles.contains(.code))
        #expect(styles.contains(.highlight))
    }

    @Test func counterAnnotationDefaultType() {
        let counter = CounterAnnotation(position: .zero, number: 1, color: .red, size: 28)
        #expect(counter.type == .counter)
    }

    @Test func effectAnnotationPreservesType() {
        let blur = EffectAnnotation(type: .blur, rect: .zero, intensity: 0.5)
        #expect(blur.type == .blur)

        let pixelate = EffectAnnotation(type: .pixelate, rect: .zero, intensity: 0.5)
        #expect(pixelate.type == .pixelate)

        let spotlight = EffectAnnotation(type: .spotlight, rect: .zero, intensity: 1.0)
        #expect(spotlight.type == .spotlight)
    }

    @Test func annotationItemIsSelectedDefaultFalse() {
        let shape = ShapeAnnotation(type: .rectangle, rect: .zero, color: .red, strokeWidth: 1, isFilled: false, cornerRadius: 0)
        #expect(shape.isSelected == false)

        let arrow = ArrowAnnotation(startPoint: .zero, endPoint: .zero, color: .red, strokeWidth: 1, isCurved: false)
        #expect(arrow.isSelected == false)

        let text = TextAnnotation(position: .zero, text: "", font: .systemFont(ofSize: 12), color: .red, backgroundColor: nil, style: .plain)
        #expect(text.isSelected == false)

        let pencil = PencilAnnotation(points: [], color: .red, strokeWidth: 1, isSmoothed: true)
        #expect(pencil.isSelected == false)

        let effect = EffectAnnotation(type: .blur, rect: .zero, intensity: 0.5)
        #expect(effect.isSelected == false)

        let counter = CounterAnnotation(position: .zero, number: 1, color: .red, size: 28)
        #expect(counter.isSelected == false)
    }

    @Test func annotationItemIsSelectedCanBeSet() {
        var shape = ShapeAnnotation(type: .rectangle, rect: .zero, color: .red, strokeWidth: 1, isFilled: false, cornerRadius: 0)
        shape.isSelected = true
        #expect(shape.isSelected)
    }
}

// MARK: - Export Service Annotation Rendering Tests

struct ExportServiceAnnotationTests {

    private func makeTestImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 400, height: 300))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: 400, height: 300))
        image.unlockFocus()
        return image
    }

    @Test func renderAnnotatedImageEmptyAnnotations() throws {
        let service = ExportService()
        let image = makeTestImage()
        let result = try #require(service.renderAnnotatedImage(
            baseImage: image, annotations: [],
            canvasSize: CGSize(width: 800, height: 600),
            imageRect: CGRect(x: 20, y: 20, width: 760, height: 560)
        ))
        #expect(result.size == image.size)
    }

    @Test func renderAnnotatedImageWithShape() {
        let service = ExportService()
        let image = makeTestImage()
        let annotations: [any AnnotationItem] = [
            ShapeAnnotation(type: .rectangle, rect: CGRect(x: 50, y: 50, width: 100, height: 80), color: .red, strokeWidth: 3, isFilled: false, cornerRadius: 0)
        ]
        let result = service.renderAnnotatedImage(baseImage: image, annotations: annotations, canvasSize: CGSize(width: 800, height: 600), imageRect: CGRect(x: 20, y: 20, width: 760, height: 560))
        #expect(result != nil)
    }

    @Test func renderAnnotatedImageWithArrow() {
        let service = ExportService()
        let image = makeTestImage()
        let annotations: [any AnnotationItem] = [
            ArrowAnnotation(startPoint: CGPoint(x: 50, y: 50), endPoint: CGPoint(x: 200, y: 150), color: .red, strokeWidth: 2, isCurved: false)
        ]
        let result = service.renderAnnotatedImage(baseImage: image, annotations: annotations, canvasSize: CGSize(width: 800, height: 600), imageRect: CGRect(x: 20, y: 20, width: 760, height: 560))
        #expect(result != nil)
    }

    @Test func renderAnnotatedImageWithText() {
        let service = ExportService()
        let image = makeTestImage()
        let annotations: [any AnnotationItem] = [
            TextAnnotation(position: CGPoint(x: 100, y: 100), text: "Test Text", font: .systemFont(ofSize: 16), color: .red, backgroundColor: nil, style: .plain)
        ]
        let result = service.renderAnnotatedImage(baseImage: image, annotations: annotations, canvasSize: CGSize(width: 800, height: 600), imageRect: CGRect(x: 20, y: 20, width: 760, height: 560))
        #expect(result != nil)
    }

    @Test func renderAnnotatedImageWithCounter() {
        let service = ExportService()
        let image = makeTestImage()
        let annotations: [any AnnotationItem] = [
            CounterAnnotation(position: CGPoint(x: 100, y: 100), number: 1, color: .red, size: 28)
        ]
        let result = service.renderAnnotatedImage(baseImage: image, annotations: annotations, canvasSize: CGSize(width: 800, height: 600), imageRect: CGRect(x: 20, y: 20, width: 760, height: 560))
        #expect(result != nil)
    }

    @Test func renderAnnotatedImageWithPencil() {
        let service = ExportService()
        let image = makeTestImage()
        let annotations: [any AnnotationItem] = [
            PencilAnnotation(points: [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 30), CGPoint(x: 100, y: 20)], color: .red, strokeWidth: 3, isSmoothed: true)
        ]
        let result = service.renderAnnotatedImage(baseImage: image, annotations: annotations, canvasSize: CGSize(width: 800, height: 600), imageRect: CGRect(x: 20, y: 20, width: 760, height: 560))
        #expect(result != nil)
    }

    @Test func renderAnnotatedImageAllAnnotationTypes() throws {
        let service = ExportService()
        let image = makeTestImage()
        let annotations: [any AnnotationItem] = [
            ShapeAnnotation(type: .rectangle, rect: CGRect(x: 10, y: 10, width: 80, height: 60), color: .red, strokeWidth: 2, isFilled: false, cornerRadius: 0),
            ShapeAnnotation(type: .ellipse, rect: CGRect(x: 100, y: 10, width: 60, height: 60), color: .blue, strokeWidth: 2, isFilled: true, cornerRadius: 0),
            ArrowAnnotation(startPoint: CGPoint(x: 200, y: 50), endPoint: CGPoint(x: 300, y: 100), color: .green, strokeWidth: 2, isCurved: false),
            ArrowAnnotation(type: .line, startPoint: CGPoint(x: 10, y: 200), endPoint: CGPoint(x: 100, y: 200), color: .orange, strokeWidth: 1, isCurved: false),
            PencilAnnotation(points: [CGPoint(x: 10, y: 150), CGPoint(x: 50, y: 130), CGPoint(x: 100, y: 160)], color: .purple, strokeWidth: 2, isSmoothed: true),
            TextAnnotation(position: CGPoint(x: 200, y: 200), text: "Test", font: .systemFont(ofSize: 14), color: .red, backgroundColor: nil, style: .plain),
            CounterAnnotation(position: CGPoint(x: 350, y: 50), number: 1, color: .red, size: 28),
        ]
        let result = try #require(service.renderAnnotatedImage(baseImage: image, annotations: annotations, canvasSize: CGSize(width: 800, height: 600), imageRect: CGRect(x: 20, y: 20, width: 760, height: 560)))
        #expect(result.size == image.size)
    }

    @Test func renderAnnotatedImageWithFilledShape() {
        let service = ExportService()
        let image = makeTestImage()
        let annotations: [any AnnotationItem] = [
            ShapeAnnotation(type: .rectangle, rect: CGRect(x: 10, y: 10, width: 80, height: 60), color: .red, strokeWidth: 2, isFilled: true, cornerRadius: 8)
        ]
        let result = service.renderAnnotatedImage(baseImage: image, annotations: annotations, canvasSize: CGSize(width: 800, height: 600), imageRect: CGRect(x: 20, y: 20, width: 760, height: 560))
        #expect(result != nil)
    }

    @Test func renderAnnotatedImageWithCurvedArrow() {
        let service = ExportService()
        let image = makeTestImage()
        let annotations: [any AnnotationItem] = [
            ArrowAnnotation(startPoint: CGPoint(x: 50, y: 50), endPoint: CGPoint(x: 200, y: 150), color: .red, strokeWidth: 2, isCurved: true, controlPoint: CGPoint(x: 125, y: 20))
        ]
        let result = service.renderAnnotatedImage(baseImage: image, annotations: annotations, canvasSize: CGSize(width: 800, height: 600), imageRect: CGRect(x: 20, y: 20, width: 760, height: 560))
        #expect(result != nil)
    }

    @Test func renderAnnotatedImageWithHighlighter() {
        let service = ExportService()
        let image = makeTestImage()
        let annotations: [any AnnotationItem] = [
            PencilAnnotation(type: .highlighter, points: [CGPoint(x: 10, y: 50), CGPoint(x: 100, y: 50), CGPoint(x: 200, y: 50)], color: .yellow.opacity(0.3), strokeWidth: 12, isSmoothed: false)
        ]
        let result = service.renderAnnotatedImage(baseImage: image, annotations: annotations, canvasSize: CGSize(width: 800, height: 600), imageRect: CGRect(x: 20, y: 20, width: 760, height: 560))
        #expect(result != nil)
    }

    @Test func renderAnnotatedImageWithLineAnnotation() {
        let service = ExportService()
        let image = makeTestImage()
        let annotations: [any AnnotationItem] = [
            ArrowAnnotation(type: .line, startPoint: CGPoint(x: 10, y: 10), endPoint: CGPoint(x: 200, y: 200), color: .green, strokeWidth: 2, isCurved: false)
        ]
        let result = service.renderAnnotatedImage(baseImage: image, annotations: annotations, canvasSize: CGSize(width: 800, height: 600), imageRect: CGRect(x: 20, y: 20, width: 760, height: 560))
        #expect(result != nil)
    }
}

// MARK: - Crop Tool Tests

@MainActor
struct CropToolTests {

    private func makeVM() -> AnnotationViewModel { AnnotationViewModel() }

    @Test func cropRectInitiallyNil() {
        let vm = makeVM()
        #expect(vm.cropRect == nil)
    }

    @Test func cropRectSetAndClear() {
        let vm = makeVM()
        let rect = CGRect(x: 50, y: 50, width: 300, height: 200)
        vm.cropRect = rect
        #expect(vm.cropRect == rect)
        vm.cropRect = nil
        #expect(vm.cropRect == nil)
    }

    @Test func cropRectPreservesDimensions() {
        let vm = makeVM()
        let rect = CGRect(x: 100, y: 100, width: 400, height: 300)
        vm.cropRect = rect
        #expect(vm.cropRect?.width == 400)
        #expect(vm.cropRect?.height == 300)
        #expect(vm.cropRect?.origin == CGPoint(x: 100, y: 100))
    }

    @Test func clearAllDoesNotAffectCropRect() {
        let vm = makeVM()
        let rect = CGRect(x: 10, y: 10, width: 200, height: 150)
        vm.cropRect = rect
        vm.addAnnotation(ShapeAnnotation(type: .rectangle, rect: .zero, color: .red, strokeWidth: 1, isFilled: false, cornerRadius: 0))
        vm.clearAll()
        #expect(vm.cropRect == rect, "Crop rect should survive clearAll")
    }
}

// MARK: - Effect Isolation Tests

@MainActor
struct EffectIsolationTests {

    private func makeVM() -> AnnotationViewModel { AnnotationViewModel() }

    @Test func blurThenCounterBothExist() {
        let vm = makeVM()
        vm.addAnnotation(EffectAnnotation(type: .blur, rect: CGRect(x: 50, y: 50, width: 100, height: 80), intensity: 0.8))
        vm.addAnnotation(CounterAnnotation(position: CGPoint(x: 200, y: 200), number: 1, color: .red, size: 28))
        #expect(vm.annotations.count == 2)
        #expect(vm.annotations[0] is EffectAnnotation)
        #expect(vm.annotations[1] is CounterAnnotation)
    }

    @Test func pixelateThenArrowBothExist() throws {
        let vm = makeVM()
        vm.addAnnotation(EffectAnnotation(type: .pixelate, rect: CGRect(x: 0, y: 0, width: 100, height: 100), intensity: 0.5))
        vm.addAnnotation(ArrowAnnotation(startPoint: CGPoint(x: 200, y: 50), endPoint: CGPoint(x: 350, y: 150), color: .red, strokeWidth: 3, isCurved: false))
        #expect(vm.annotations.count == 2)
        let effect = try #require(vm.annotations[0] as? EffectAnnotation)
        #expect(effect.type == .pixelate)
        #expect(vm.annotations[1] is ArrowAnnotation)
    }

    @Test func spotlightThenTextBothExist() throws {
        let vm = makeVM()
        vm.addAnnotation(EffectAnnotation(type: .spotlight, rect: CGRect(x: 100, y: 100, width: 200, height: 200), intensity: 1.0))
        vm.addAnnotation(TextAnnotation(position: CGPoint(x: 150, y: 150), text: "Spotlight text", font: .systemFont(ofSize: 16), color: .white, backgroundColor: nil, style: .plain))
        #expect(vm.annotations.count == 2)
        let text = try #require(vm.annotations[1] as? TextAnnotation)
        #expect(text.text == "Spotlight text")
    }

    @Test func multipleEffectsAllPreserved() {
        let vm = makeVM()
        vm.addAnnotation(EffectAnnotation(type: .blur, rect: CGRect(x: 10, y: 10, width: 50, height: 50), intensity: 0.5))
        vm.addAnnotation(EffectAnnotation(type: .pixelate, rect: CGRect(x: 80, y: 80, width: 50, height: 50), intensity: 0.7))
        vm.addAnnotation(EffectAnnotation(type: .spotlight, rect: CGRect(x: 150, y: 150, width: 100, height: 100), intensity: 1.0))
        vm.addAnnotation(CounterAnnotation(position: CGPoint(x: 300, y: 50), number: 1, color: .red, size: 28))
        vm.addAnnotation(ArrowAnnotation(startPoint: .zero, endPoint: CGPoint(x: 100, y: 100), color: .green, strokeWidth: 2, isCurved: false))
        #expect(vm.annotations.count == 5)
    }

    @Test func effectRenderingDoesNotCrash() {
        let service = ExportService()
        let image = NSImage(size: NSSize(width: 200, height: 200))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath.fill(NSRect(origin: .zero, size: image.size))
        image.unlockFocus()

        let annotations: [any AnnotationItem] = [
            EffectAnnotation(type: .blur, rect: CGRect(x: 10, y: 10, width: 50, height: 50), intensity: 0.8),
            CounterAnnotation(position: CGPoint(x: 150, y: 150), number: 1, color: .red, size: 28),
            EffectAnnotation(type: .pixelate, rect: CGRect(x: 60, y: 60, width: 50, height: 50), intensity: 0.5),
            ArrowAnnotation(startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 100, y: 100), color: .blue, strokeWidth: 2, isCurved: false),
        ]
        let result = service.renderAnnotatedImage(baseImage: image, annotations: annotations, canvasSize: CGSize(width: 400, height: 400), imageRect: CGRect(x: 0, y: 0, width: 400, height: 400))
        #expect(result != nil, "Rendering effects + annotations should not crash")
    }
}

// MARK: - Multi-Tool Workflow Integration Tests

@MainActor
struct AnnotationWorkflowTests {

    @Test func completeWorkflowAddMultipleTypesUndoAllRedoAll() {
        let vm = AnnotationViewModel()
        vm.addAnnotation(ShapeAnnotation(type: .rectangle, rect: CGRect(x: 10, y: 10, width: 100, height: 50), color: .red, strokeWidth: 2, isFilled: false, cornerRadius: 0))
        vm.addAnnotation(ArrowAnnotation(startPoint: CGPoint(x: 200, y: 50), endPoint: CGPoint(x: 300, y: 150), color: .blue, strokeWidth: 3, isCurved: false))
        vm.addAnnotation(TextAnnotation(position: CGPoint(x: 100, y: 200), text: "Hello", font: .systemFont(ofSize: 16), color: .green, backgroundColor: nil, style: .plain))
        let num = vm.nextCounterNumber()
        vm.addAnnotation(CounterAnnotation(position: CGPoint(x: 350, y: 50), number: num, color: .red, size: 28))
        vm.addAnnotation(PencilAnnotation(points: [CGPoint(x: 10, y: 300), CGPoint(x: 50, y: 280), CGPoint(x: 100, y: 310)], color: .purple, strokeWidth: 2, isSmoothed: true))
        #expect(vm.annotations.count == 5)

        vm.undo(); vm.undo(); vm.undo(); vm.undo(); vm.undo()
        #expect(vm.annotations.count == 0)
        #expect(vm.canUndo == false)
        #expect(vm.canRedo)

        vm.redo(); vm.redo(); vm.redo(); vm.redo(); vm.redo()
        #expect(vm.annotations.count == 5)
        #expect(vm.canUndo)
        #expect(vm.canRedo == false)
    }

    @Test func selectAndRemoveWorkflow() {
        let vm = AnnotationViewModel()
        let shape = ShapeAnnotation(type: .rectangle, rect: CGRect(x: 50, y: 50, width: 100, height: 100), color: .red, strokeWidth: 2, isFilled: false, cornerRadius: 0)
        vm.addAnnotation(shape)
        vm.addAnnotation(ArrowAnnotation(startPoint: CGPoint(x: 250, y: 250), endPoint: CGPoint(x: 350, y: 350), color: .blue, strokeWidth: 2, isCurved: false))
        vm.selectAnnotation(at: CGPoint(x: 75, y: 75))
        #expect(vm.annotations[0].isSelected)
        #expect(vm.annotations[1].isSelected == false)
        vm.removeAnnotation(id: shape.id)
        #expect(vm.annotations.count == 1)
        #expect(vm.annotations[0] is ArrowAnnotation)
    }

    @Test func textEditAndUndoWorkflow() throws {
        let vm = AnnotationViewModel()
        let textAnnotation = TextAnnotation(position: CGPoint(x: 100, y: 100), text: "Initial", font: .systemFont(ofSize: 14), color: .red, backgroundColor: nil, style: .plain)
        vm.addAnnotation(textAnnotation)

        vm.updateText(id: textAnnotation.id, newText: "Updated")
        let updated = try #require(vm.annotations[0] as? TextAnnotation)
        #expect(updated.text == "Updated")

        vm.undo()
        let restored = try #require(vm.annotations[0] as? TextAnnotation)
        #expect(restored.text == "Initial")

        vm.redo()
        let redone = try #require(vm.annotations[0] as? TextAnnotation)
        #expect(redone.text == "Updated")
    }

    @Test func hitTestPencilAnnotation() {
        let vm = AnnotationViewModel()
        vm.addAnnotation(PencilAnnotation(
            points: [CGPoint(x: 50, y: 50), CGPoint(x: 100, y: 50), CGPoint(x: 150, y: 50)],
            color: .red, strokeWidth: 3, isSmoothed: false
        ))
        vm.selectAnnotation(at: CGPoint(x: 100, y: 52))
        #expect(vm.annotations[0].isSelected)
        vm.selectAnnotation(at: CGPoint(x: 300, y: 300))
        #expect(vm.annotations[0].isSelected == false)
    }

    @Test func hitTestEffectAnnotation() {
        let vm = AnnotationViewModel()
        vm.addAnnotation(EffectAnnotation(type: .blur, rect: CGRect(x: 50, y: 50, width: 100, height: 80), intensity: 0.8))
        vm.selectAnnotation(at: CGPoint(x: 100, y: 90))
        #expect(vm.annotations[0].isSelected)
        vm.selectAnnotation(at: CGPoint(x: 300, y: 300))
        #expect(vm.annotations[0].isSelected == false)
    }
}

// MARK: - BlurEffectRenderer Tests

struct BlurEffectRendererTests {

    private func makeColorTestImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 200, height: 200))
        image.lockFocus()
        NSColor.red.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: 100, width: 100, height: 100))
        NSColor.blue.setFill()
        NSBezierPath.fill(NSRect(x: 100, y: 100, width: 100, height: 100))
        NSColor.green.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: 100, height: 100))
        NSColor.yellow.setFill()
        NSBezierPath.fill(NSRect(x: 100, y: 0, width: 100, height: 100))
        image.unlockFocus()
        return image
    }

    @Test func pixelateRegionReturnsValidImage() throws {
        let source = makeColorTestImage()
        let region = CGRect(x: 10, y: 10, width: 100, height: 100)
        let result = try #require(BlurEffectRenderer.pixelateRegion(sourceImage: source, region: region, pixelSize: 20))
        #expect(result.size.width == 100)
        #expect(result.size.height == 100)
    }

    @Test func pixelateRegionDifferentPixelSizes() {
        let source = makeColorTestImage()
        let region = CGRect(x: 0, y: 0, width: 100, height: 100)
        let small = BlurEffectRenderer.pixelateRegion(sourceImage: source, region: region, pixelSize: 4)
        let large = BlurEffectRenderer.pixelateRegion(sourceImage: source, region: region, pixelSize: 30)
        #expect(small != nil)
        #expect(large != nil)
    }

    @Test func pixelateRegionZeroSizeReturnsNil() {
        let source = makeColorTestImage()
        let zeroRegion = CGRect(x: 0, y: 0, width: 0, height: 0)
        let result = BlurEffectRenderer.pixelateRegion(sourceImage: source, region: zeroRegion)
        #expect(result == nil)
    }

    @Test func pixelateRegionOutOfBoundsDoesNotCrash() {
        let source = makeColorTestImage()
        let outsideRegion = CGRect(x: 500, y: 500, width: 100, height: 100)
        _ = BlurEffectRenderer.pixelateRegion(sourceImage: source, region: outsideRegion)
        // Test passes if no crash
    }

    @Test func blurRegionReturnsValidImage() throws {
        let source = makeColorTestImage()
        let region = CGRect(x: 10, y: 10, width: 100, height: 100)
        let result = try #require(BlurEffectRenderer.blurRegion(sourceImage: source, region: region, radius: 10))
        #expect(result.size.width == 100)
        #expect(result.size.height == 100)
    }

    @Test func blurRegionLargeRadius() {
        let source = makeColorTestImage()
        let region = CGRect(x: 0, y: 0, width: 100, height: 100)
        let result = BlurEffectRenderer.blurRegion(sourceImage: source, region: region, radius: 50)
        #expect(result != nil)
    }

    @Test func blurRegionZeroRadius() {
        let source = makeColorTestImage()
        let region = CGRect(x: 0, y: 0, width: 100, height: 100)
        let result = BlurEffectRenderer.blurRegion(sourceImage: source, region: region, radius: 0)
        #expect(result != nil)
    }

    @Test func blurRegionZeroSizeReturnsNil() {
        let source = makeColorTestImage()
        let result = BlurEffectRenderer.blurRegion(sourceImage: source, region: .zero)
        #expect(result == nil)
    }

    @Test func pixelateRegionFullImage() throws {
        let source = makeColorTestImage()
        let region = CGRect(origin: .zero, size: source.size)
        let result = try #require(BlurEffectRenderer.pixelateRegion(sourceImage: source, region: region, pixelSize: 20))
        #expect(result.size.width == 200)
        #expect(result.size.height == 200)
    }
}

// MARK: - Export Service with Effects Tests

struct ExportServiceEffectTests {

    private func makeTestImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 400, height: 300))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: 400, height: 300))
        NSColor.red.setFill()
        NSBezierPath.fill(NSRect(x: 50, y: 50, width: 100, height: 100))
        NSColor.blue.setFill()
        NSBezierPath.fill(NSRect(x: 200, y: 100, width: 150, height: 80))
        image.unlockFocus()
        return image
    }

    @Test func exportWithPixelateEffect() throws {
        let service = ExportService()
        let image = makeTestImage()
        let annotations: [any AnnotationItem] = [
            EffectAnnotation(type: .pixelate, rect: CGRect(x: 100, y: 100, width: 200, height: 150), intensity: 0.8)
        ]
        let result = try #require(service.renderAnnotatedImage(baseImage: image, annotations: annotations, canvasSize: CGSize(width: 800, height: 600), imageRect: CGRect(x: 0, y: 0, width: 800, height: 600)))
        #expect(result.size == image.size)
    }

    @Test func exportWithBlurEffect() {
        let service = ExportService()
        let image = makeTestImage()
        let annotations: [any AnnotationItem] = [
            EffectAnnotation(type: .blur, rect: CGRect(x: 50, y: 50, width: 200, height: 100), intensity: 0.7)
        ]
        let result = service.renderAnnotatedImage(baseImage: image, annotations: annotations, canvasSize: CGSize(width: 800, height: 600), imageRect: CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(result != nil, "Export with blur should succeed")
    }

    @Test func exportWithSpotlightEffect() {
        let service = ExportService()
        let image = makeTestImage()
        let annotations: [any AnnotationItem] = [
            EffectAnnotation(type: .spotlight, rect: CGRect(x: 100, y: 100, width: 200, height: 150), intensity: 1.0)
        ]
        let result = service.renderAnnotatedImage(baseImage: image, annotations: annotations, canvasSize: CGSize(width: 800, height: 600), imageRect: CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(result != nil, "Export with spotlight should succeed")
    }

    @Test func exportMixedEffectsAndAnnotations() throws {
        let service = ExportService()
        let image = makeTestImage()
        let annotations: [any AnnotationItem] = [
            EffectAnnotation(type: .pixelate, rect: CGRect(x: 50, y: 50, width: 100, height: 80), intensity: 0.8),
            EffectAnnotation(type: .blur, rect: CGRect(x: 200, y: 100, width: 100, height: 80), intensity: 0.6),
            ShapeAnnotation(type: .rectangle, rect: CGRect(x: 10, y: 10, width: 80, height: 60), color: .red, strokeWidth: 2, isFilled: false, cornerRadius: 0),
            ArrowAnnotation(startPoint: CGPoint(x: 200, y: 50), endPoint: CGPoint(x: 350, y: 150), color: .green, strokeWidth: 2, isCurved: false),
            CounterAnnotation(position: CGPoint(x: 350, y: 50), number: 1, color: .red, size: 28),
            TextAnnotation(position: CGPoint(x: 100, y: 200), text: "Test", font: .systemFont(ofSize: 14), color: .red, backgroundColor: nil, style: .plain),
        ]
        let result = try #require(service.renderAnnotatedImage(baseImage: image, annotations: annotations, canvasSize: CGSize(width: 800, height: 600), imageRect: CGRect(x: 0, y: 0, width: 800, height: 600)))
        #expect(result.size == image.size)
    }

    @Test func exportMultiplePixelateEffects() {
        let service = ExportService()
        let image = makeTestImage()
        let annotations: [any AnnotationItem] = [
            EffectAnnotation(type: .pixelate, rect: CGRect(x: 10, y: 10, width: 80, height: 60), intensity: 0.5),
            EffectAnnotation(type: .pixelate, rect: CGRect(x: 150, y: 80, width: 100, height: 80), intensity: 1.0),
            EffectAnnotation(type: .pixelate, rect: CGRect(x: 300, y: 20, width: 60, height: 60), intensity: 0.3),
        ]
        let result = service.renderAnnotatedImage(baseImage: image, annotations: annotations, canvasSize: CGSize(width: 800, height: 600), imageRect: CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(result != nil, "Multiple pixelate effects should render")
    }

    @Test func exportEffectWithZeroIntensity() {
        let service = ExportService()
        let image = makeTestImage()
        let annotations: [any AnnotationItem] = [
            EffectAnnotation(type: .blur, rect: CGRect(x: 50, y: 50, width: 100, height: 100), intensity: 0.0),
        ]
        let result = service.renderAnnotatedImage(baseImage: image, annotations: annotations, canvasSize: CGSize(width: 800, height: 600), imageRect: CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(result != nil, "Zero-intensity effect should not crash")
    }
}
