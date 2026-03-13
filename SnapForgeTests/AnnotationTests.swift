import XCTest
@testable import SnapForge
import SwiftUI

/// Comprehensive tests for all annotation tools and the annotation view model
final class AnnotationViewModelTests: XCTestCase {

    // MARK: - Setup

    private func makeVM() -> AnnotationViewModel {
        AnnotationViewModel()
    }

    // MARK: - Initial State

    func testInitialState() {
        let vm = makeVM()
        XCTAssertEqual(vm.selectedTool, .select)
        XCTAssertEqual(vm.strokeWidth, 3)
        XCTAssertEqual(vm.opacity, 1.0)
        XCTAssertFalse(vm.fillShape)
        XCTAssertTrue(vm.annotations.isEmpty)
        XCTAssertFalse(vm.canUndo)
        XCTAssertFalse(vm.canRedo)
        XCTAssertNil(vm.cropRect)
    }

    // MARK: - Undo / Redo

    func testUndo_restoresPreviousState() {
        let vm = makeVM()
        vm.addAnnotation(ShapeAnnotation(
            type: .rectangle,
            rect: CGRect(x: 0, y: 0, width: 100, height: 50),
            color: .red, strokeWidth: 2, isFilled: false, cornerRadius: 0
        ))
        XCTAssertEqual(vm.annotations.count, 1)
        XCTAssertTrue(vm.canUndo)

        vm.undo()
        XCTAssertEqual(vm.annotations.count, 0)
        XCTAssertTrue(vm.canRedo)
    }

    func testRedo_restoresUndoneState() {
        let vm = makeVM()
        vm.addAnnotation(ShapeAnnotation(
            type: .ellipse,
            rect: CGRect(x: 10, y: 10, width: 80, height: 80),
            color: .blue, strokeWidth: 3, isFilled: true, cornerRadius: 0
        ))
        vm.undo()
        XCTAssertEqual(vm.annotations.count, 0)

        vm.redo()
        XCTAssertEqual(vm.annotations.count, 1)
        XCTAssertFalse(vm.canRedo)
    }

    func testAddAnnotation_clearsRedoStack() {
        let vm = makeVM()
        vm.addAnnotation(ShapeAnnotation(
            type: .rectangle, rect: .zero, color: .red,
            strokeWidth: 1, isFilled: false, cornerRadius: 0
        ))
        vm.undo()
        XCTAssertTrue(vm.canRedo)

        vm.addAnnotation(ShapeAnnotation(
            type: .ellipse, rect: .zero, color: .blue,
            strokeWidth: 1, isFilled: false, cornerRadius: 0
        ))
        XCTAssertFalse(vm.canRedo, "Adding new annotation should clear redo stack")
    }

    func testMultipleUndoRedo() {
        let vm = makeVM()
        vm.addAnnotation(ShapeAnnotation(type: .rectangle, rect: .zero, color: .red, strokeWidth: 1, isFilled: false, cornerRadius: 0))
        vm.addAnnotation(ShapeAnnotation(type: .ellipse, rect: .zero, color: .blue, strokeWidth: 1, isFilled: false, cornerRadius: 0))
        vm.addAnnotation(ArrowAnnotation(startPoint: .zero, endPoint: CGPoint(x: 100, y: 100), color: .green, strokeWidth: 2, isCurved: false))

        XCTAssertEqual(vm.annotations.count, 3)

        vm.undo() // Back to 2
        XCTAssertEqual(vm.annotations.count, 2)

        vm.undo() // Back to 1
        XCTAssertEqual(vm.annotations.count, 1)

        vm.redo() // Forward to 2
        XCTAssertEqual(vm.annotations.count, 2)

        vm.undo() // Back to 1
        vm.undo() // Back to 0
        XCTAssertEqual(vm.annotations.count, 0)
        XCTAssertFalse(vm.canUndo)
    }

    func testUndo_whenEmpty_doesNothing() {
        let vm = makeVM()
        vm.undo()
        XCTAssertEqual(vm.annotations.count, 0)
    }

    func testRedo_whenEmpty_doesNothing() {
        let vm = makeVM()
        vm.redo()
        XCTAssertEqual(vm.annotations.count, 0)
    }

    // MARK: - Add Annotations

    func testAddShapeAnnotation_rectangle() {
        let vm = makeVM()
        let rect = CGRect(x: 50, y: 50, width: 200, height: 100)
        vm.addAnnotation(ShapeAnnotation(
            type: .rectangle, rect: rect, color: .red,
            strokeWidth: 3, isFilled: false, cornerRadius: 0
        ))

        XCTAssertEqual(vm.annotations.count, 1)
        let shape = vm.annotations[0] as? ShapeAnnotation
        XCTAssertNotNil(shape)
        XCTAssertEqual(shape?.type, .rectangle)
        XCTAssertEqual(shape?.rect, rect)
        XCTAssertFalse(shape?.isFilled ?? true)
    }

    func testAddShapeAnnotation_ellipse() {
        let vm = makeVM()
        vm.addAnnotation(ShapeAnnotation(
            type: .ellipse, rect: CGRect(x: 0, y: 0, width: 100, height: 100),
            color: .blue, strokeWidth: 2, isFilled: true, cornerRadius: 0
        ))

        let shape = vm.annotations[0] as? ShapeAnnotation
        XCTAssertEqual(shape?.type, .ellipse)
        XCTAssertTrue(shape?.isFilled ?? false)
    }

    func testAddArrowAnnotation() {
        let vm = makeVM()
        let start = CGPoint(x: 10, y: 20)
        let end = CGPoint(x: 200, y: 150)
        vm.addAnnotation(ArrowAnnotation(
            startPoint: start, endPoint: end,
            color: .red, strokeWidth: 2, isCurved: false
        ))

        let arrow = vm.annotations[0] as? ArrowAnnotation
        XCTAssertNotNil(arrow)
        XCTAssertEqual(arrow?.type, .arrow)
        XCTAssertEqual(arrow?.startPoint, start)
        XCTAssertEqual(arrow?.endPoint, end)
        XCTAssertFalse(arrow?.isCurved ?? true)
    }

    func testAddArrowAnnotation_asLine() {
        let vm = makeVM()
        vm.addAnnotation(ArrowAnnotation(
            type: .line,
            startPoint: .zero, endPoint: CGPoint(x: 100, y: 0),
            color: .green, strokeWidth: 1, isCurved: false
        ))

        let line = vm.annotations[0] as? ArrowAnnotation
        XCTAssertEqual(line?.type, .line, "Line type should be .line, not .arrow")
    }

    func testAddPencilAnnotation() {
        let vm = makeVM()
        let points: [CGPoint] = [
            CGPoint(x: 10, y: 10),
            CGPoint(x: 20, y: 15),
            CGPoint(x: 30, y: 12),
            CGPoint(x: 40, y: 20),
            CGPoint(x: 50, y: 18)
        ]
        vm.addAnnotation(PencilAnnotation(
            points: points, color: .red, strokeWidth: 2, isSmoothed: true
        ))

        let pencil = vm.annotations[0] as? PencilAnnotation
        XCTAssertNotNil(pencil)
        XCTAssertEqual(pencil?.points.count, 5)
        XCTAssertTrue(pencil?.isSmoothed ?? false)
        XCTAssertEqual(pencil?.type, .pencil)
    }

    func testAddPencilAnnotation_asHighlighter() {
        let vm = makeVM()
        vm.addAnnotation(PencilAnnotation(
            type: .highlighter,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 200, y: 0)],
            color: .yellow.opacity(0.3),
            strokeWidth: 12,
            isSmoothed: false
        ))

        let highlighter = vm.annotations[0] as? PencilAnnotation
        XCTAssertEqual(highlighter?.type, .highlighter)
        XCTAssertFalse(highlighter?.isSmoothed ?? true)
        XCTAssertGreaterThanOrEqual(highlighter?.strokeWidth ?? 0, 12)
    }

    func testAddTextAnnotation() {
        let vm = makeVM()
        vm.addAnnotation(TextAnnotation(
            position: CGPoint(x: 100, y: 100),
            text: "Hello World",
            font: .systemFont(ofSize: 16),
            color: .red,
            backgroundColor: nil,
            style: .plain
        ))

        let text = vm.annotations[0] as? TextAnnotation
        XCTAssertNotNil(text)
        XCTAssertEqual(text?.text, "Hello World")
        XCTAssertEqual(text?.style, .plain)
    }

    func testAddTextAnnotation_boxedStyle() {
        let vm = makeVM()
        vm.addAnnotation(TextAnnotation(
            position: CGPoint(x: 50, y: 50),
            text: "Boxed",
            font: .systemFont(ofSize: 14),
            color: .blue,
            backgroundColor: .white,
            style: .boxed
        ))

        let text = vm.annotations[0] as? TextAnnotation
        XCTAssertEqual(text?.style, .boxed)
        XCTAssertNotNil(text?.backgroundColor)
    }

    func testAddCounterAnnotation() {
        let vm = makeVM()
        let num = vm.nextCounterNumber()
        vm.addAnnotation(CounterAnnotation(
            position: CGPoint(x: 200, y: 200),
            number: num,
            color: .red,
            size: 28
        ))

        let counter = vm.annotations[0] as? CounterAnnotation
        XCTAssertNotNil(counter)
        XCTAssertEqual(counter?.number, 1)
        XCTAssertEqual(counter?.size, 28)
    }

    func testCounterAutoIncrement() {
        let vm = makeVM()
        XCTAssertEqual(vm.nextCounterNumber(), 1)
        XCTAssertEqual(vm.nextCounterNumber(), 2)
        XCTAssertEqual(vm.nextCounterNumber(), 3)
    }

    func testCounterResets_onClearAll() {
        let vm = makeVM()
        _ = vm.nextCounterNumber()
        _ = vm.nextCounterNumber()
        vm.addAnnotation(CounterAnnotation(
            position: .zero, number: 2, color: .red, size: 28
        ))

        vm.clearAll()

        // Counter should reset
        XCTAssertEqual(vm.nextCounterNumber(), 1)
    }

    func testAddEffectAnnotation_blur() {
        let vm = makeVM()
        vm.addAnnotation(EffectAnnotation(
            type: .blur,
            rect: CGRect(x: 50, y: 50, width: 100, height: 60),
            intensity: 0.8
        ))

        let effect = vm.annotations[0] as? EffectAnnotation
        XCTAssertEqual(effect?.type, .blur)
        XCTAssertEqual(effect?.intensity, 0.8)
    }

    func testAddEffectAnnotation_pixelate() {
        let vm = makeVM()
        vm.addAnnotation(EffectAnnotation(
            type: .pixelate,
            rect: CGRect(x: 0, y: 0, width: 100, height: 100),
            intensity: 0.5
        ))

        let effect = vm.annotations[0] as? EffectAnnotation
        XCTAssertEqual(effect?.type, .pixelate)
    }

    func testAddEffectAnnotation_spotlight() {
        let vm = makeVM()
        vm.addAnnotation(EffectAnnotation(
            type: .spotlight,
            rect: CGRect(x: 100, y: 100, width: 200, height: 200),
            intensity: 1.0
        ))

        let effect = vm.annotations[0] as? EffectAnnotation
        XCTAssertEqual(effect?.type, .spotlight)
    }

    // MARK: - Remove Annotation

    func testRemoveAnnotation_byID() {
        let vm = makeVM()
        let annotation = ShapeAnnotation(
            type: .rectangle, rect: .zero, color: .red,
            strokeWidth: 1, isFilled: false, cornerRadius: 0
        )
        vm.addAnnotation(annotation)
        XCTAssertEqual(vm.annotations.count, 1)

        vm.removeAnnotation(id: annotation.id)
        XCTAssertEqual(vm.annotations.count, 0)
    }

    func testRemoveAnnotation_nonexistentID_doesNothing() {
        let vm = makeVM()
        vm.addAnnotation(ShapeAnnotation(
            type: .rectangle, rect: .zero, color: .red,
            strokeWidth: 1, isFilled: false, cornerRadius: 0
        ))

        vm.removeAnnotation(id: UUID())
        XCTAssertEqual(vm.annotations.count, 1)
    }

    // MARK: - Clear All

    func testClearAll_removesAllAnnotations() {
        let vm = makeVM()
        vm.addAnnotation(ShapeAnnotation(type: .rectangle, rect: .zero, color: .red, strokeWidth: 1, isFilled: false, cornerRadius: 0))
        vm.addAnnotation(ArrowAnnotation(startPoint: .zero, endPoint: CGPoint(x: 100, y: 100), color: .blue, strokeWidth: 2, isCurved: false))

        vm.clearAll()
        XCTAssertTrue(vm.annotations.isEmpty)
        XCTAssertTrue(vm.canUndo, "Should be undoable")
    }

    func testClearAll_whenEmpty_doesNotAddUndoState() {
        let vm = makeVM()
        vm.clearAll()
        XCTAssertFalse(vm.canUndo, "Empty clearAll should not add undo state")
    }

    // MARK: - Text Update

    func testUpdateText_changesTextContent() {
        let vm = makeVM()
        let textAnnotation = TextAnnotation(
            position: CGPoint(x: 100, y: 100),
            text: "Original",
            font: .systemFont(ofSize: 14),
            color: .red,
            backgroundColor: nil,
            style: .plain
        )
        vm.addAnnotation(textAnnotation)

        vm.updateText(id: textAnnotation.id, newText: "Updated Text")

        let updated = vm.annotations[0] as? TextAnnotation
        XCTAssertEqual(updated?.text, "Updated Text")
    }

    func testUpdateText_nonexistentID_doesNothing() {
        let vm = makeVM()
        vm.addAnnotation(TextAnnotation(
            position: .zero, text: "Test", font: .systemFont(ofSize: 14),
            color: .red, backgroundColor: nil, style: .plain
        ))

        vm.updateText(id: UUID(), newText: "Nope")
        let text = vm.annotations[0] as? TextAnnotation
        XCTAssertEqual(text?.text, "Test")
    }

    func testUpdateText_onNonTextAnnotation_doesNothing() {
        let vm = makeVM()
        let shape = ShapeAnnotation(type: .rectangle, rect: .zero, color: .red, strokeWidth: 1, isFilled: false, cornerRadius: 0)
        vm.addAnnotation(shape)

        vm.updateText(id: shape.id, newText: "Should not work")
        XCTAssertEqual(vm.annotations.count, 1)
    }

    // MARK: - Selection / Hit Testing

    func testSelectAnnotation_shape() {
        let vm = makeVM()
        let shape = ShapeAnnotation(
            type: .rectangle,
            rect: CGRect(x: 50, y: 50, width: 100, height: 100),
            color: .red, strokeWidth: 2, isFilled: false, cornerRadius: 0
        )
        vm.addAnnotation(shape)

        vm.selectAnnotation(at: CGPoint(x: 75, y: 75))
        XCTAssertTrue(vm.annotations[0].isSelected)
    }

    func testSelectAnnotation_missedClick_deselectsAll() {
        let vm = makeVM()
        var shape = ShapeAnnotation(
            type: .rectangle,
            rect: CGRect(x: 50, y: 50, width: 100, height: 100),
            color: .red, strokeWidth: 2, isFilled: false, cornerRadius: 0
        )
        shape.isSelected = true
        vm.addAnnotation(shape)

        vm.selectAnnotation(at: CGPoint(x: 500, y: 500))
        XCTAssertFalse(vm.annotations[0].isSelected)
    }

    func testSelectAnnotation_arrow() {
        let vm = makeVM()
        vm.addAnnotation(ArrowAnnotation(
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 100, y: 100),
            color: .red, strokeWidth: 2, isCurved: false
        ))

        // Click near the middle of the arrow
        vm.selectAnnotation(at: CGPoint(x: 50, y: 50))
        XCTAssertTrue(vm.annotations[0].isSelected)
    }

    func testSelectAnnotation_counter() {
        let vm = makeVM()
        vm.addAnnotation(CounterAnnotation(
            position: CGPoint(x: 100, y: 100),
            number: 1, color: .red, size: 28
        ))

        vm.selectAnnotation(at: CGPoint(x: 105, y: 105))
        XCTAssertTrue(vm.annotations[0].isSelected)
    }

    func testSelectAnnotation_topmostWins() {
        let vm = makeVM()
        // Overlapping shapes — topmost (last added) should be selected
        vm.addAnnotation(ShapeAnnotation(
            type: .rectangle,
            rect: CGRect(x: 0, y: 0, width: 200, height: 200),
            color: .red, strokeWidth: 1, isFilled: false, cornerRadius: 0
        ))
        vm.addAnnotation(ShapeAnnotation(
            type: .rectangle,
            rect: CGRect(x: 50, y: 50, width: 100, height: 100),
            color: .blue, strokeWidth: 1, isFilled: false, cornerRadius: 0
        ))

        vm.selectAnnotation(at: CGPoint(x: 75, y: 75))
        XCTAssertFalse(vm.annotations[0].isSelected, "Bottom shape should NOT be selected")
        XCTAssertTrue(vm.annotations[1].isSelected, "Top shape SHOULD be selected")
    }

    // MARK: - Crop Rect

    func testCropRect_canBeSet() {
        let vm = makeVM()
        let rect = CGRect(x: 10, y: 10, width: 200, height: 150)
        vm.cropRect = rect
        XCTAssertEqual(vm.cropRect, rect)
    }
}

// MARK: - Annotation Types Tests

final class AnnotationTypeTests: XCTestCase {

    func testAllCases_count() {
        XCTAssertEqual(AnnotationType.allCases.count, 13)
    }

    func testAllCases_haveIcons() {
        for tool in AnnotationType.allCases {
            XCTAssertFalse(tool.icon.isEmpty, "\(tool.rawValue) should have an icon")
        }
    }

    func testAllCases_haveRawValues() {
        for tool in AnnotationType.allCases {
            XCTAssertFalse(tool.rawValue.isEmpty)
        }
    }

    func testIdentifiers_areUnique() {
        let ids = AnnotationType.allCases.map { $0.id }
        let uniqueIds = Set(ids)
        XCTAssertEqual(ids.count, uniqueIds.count, "All tool IDs should be unique")
    }
}

// MARK: - Annotation Item Model Tests

final class AnnotationItemModelTests: XCTestCase {

    func testShapeAnnotation_hasUniqueID() {
        let a = ShapeAnnotation(type: .rectangle, rect: .zero, color: .red, strokeWidth: 1, isFilled: false, cornerRadius: 0)
        let b = ShapeAnnotation(type: .rectangle, rect: .zero, color: .red, strokeWidth: 1, isFilled: false, cornerRadius: 0)
        XCTAssertNotEqual(a.id, b.id)
    }

    func testArrowAnnotation_defaultType() {
        let arrow = ArrowAnnotation(startPoint: .zero, endPoint: .zero, color: .red, strokeWidth: 1, isCurved: false)
        XCTAssertEqual(arrow.type, .arrow)
    }

    func testArrowAnnotation_lineType() {
        let line = ArrowAnnotation(type: .line, startPoint: .zero, endPoint: .zero, color: .red, strokeWidth: 1, isCurved: false)
        XCTAssertEqual(line.type, .line)
    }

    func testPencilAnnotation_defaultType() {
        let pencil = PencilAnnotation(points: [], color: .red, strokeWidth: 1, isSmoothed: true)
        XCTAssertEqual(pencil.type, .pencil)
    }

    func testPencilAnnotation_highlighterType() {
        let hl = PencilAnnotation(type: .highlighter, points: [], color: .yellow, strokeWidth: 12, isSmoothed: false)
        XCTAssertEqual(hl.type, .highlighter)
    }

    func testTextAnnotation_allStyles() {
        let styles = TextAnnotation.TextStyle.allCases
        XCTAssertEqual(styles.count, 7)
        XCTAssertTrue(styles.contains(.plain))
        XCTAssertTrue(styles.contains(.boxed))
        XCTAssertTrue(styles.contains(.callout))
        XCTAssertTrue(styles.contains(.code))
        XCTAssertTrue(styles.contains(.highlight))
    }

    func testCounterAnnotation_defaultType() {
        let counter = CounterAnnotation(position: .zero, number: 1, color: .red, size: 28)
        XCTAssertEqual(counter.type, .counter)
    }

    func testEffectAnnotation_preservesType() {
        let blur = EffectAnnotation(type: .blur, rect: .zero, intensity: 0.5)
        XCTAssertEqual(blur.type, .blur)

        let pixelate = EffectAnnotation(type: .pixelate, rect: .zero, intensity: 0.5)
        XCTAssertEqual(pixelate.type, .pixelate)

        let spotlight = EffectAnnotation(type: .spotlight, rect: .zero, intensity: 1.0)
        XCTAssertEqual(spotlight.type, .spotlight)
    }

    func testAnnotationItem_isSelected_defaultFalse() {
        let shape = ShapeAnnotation(type: .rectangle, rect: .zero, color: .red, strokeWidth: 1, isFilled: false, cornerRadius: 0)
        XCTAssertFalse(shape.isSelected)

        let arrow = ArrowAnnotation(startPoint: .zero, endPoint: .zero, color: .red, strokeWidth: 1, isCurved: false)
        XCTAssertFalse(arrow.isSelected)

        let text = TextAnnotation(position: .zero, text: "", font: .systemFont(ofSize: 12), color: .red, backgroundColor: nil, style: .plain)
        XCTAssertFalse(text.isSelected)

        let pencil = PencilAnnotation(points: [], color: .red, strokeWidth: 1, isSmoothed: true)
        XCTAssertFalse(pencil.isSelected)

        let effect = EffectAnnotation(type: .blur, rect: .zero, intensity: 0.5)
        XCTAssertFalse(effect.isSelected)

        let counter = CounterAnnotation(position: .zero, number: 1, color: .red, size: 28)
        XCTAssertFalse(counter.isSelected)
    }

    func testAnnotationItem_isSelected_canBeSet() {
        var shape = ShapeAnnotation(type: .rectangle, rect: .zero, color: .red, strokeWidth: 1, isFilled: false, cornerRadius: 0)
        shape.isSelected = true
        XCTAssertTrue(shape.isSelected)
    }
}

// MARK: - Export Service Annotation Rendering Tests

final class ExportServiceAnnotationTests: XCTestCase {

    private func makeTestImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 400, height: 300))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: 400, height: 300))
        image.unlockFocus()
        return image
    }

    func testRenderAnnotatedImage_emptyAnnotations() {
        let service = ExportService()
        let image = makeTestImage()

        let result = service.renderAnnotatedImage(
            baseImage: image,
            annotations: [],
            canvasSize: CGSize(width: 800, height: 600),
            imageRect: CGRect(x: 20, y: 20, width: 760, height: 560)
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.size, image.size)
    }

    func testRenderAnnotatedImage_withShape() {
        let service = ExportService()
        let image = makeTestImage()

        let annotations: [any AnnotationItem] = [
            ShapeAnnotation(type: .rectangle,
                          rect: CGRect(x: 50, y: 50, width: 100, height: 80),
                          color: .red, strokeWidth: 3, isFilled: false, cornerRadius: 0)
        ]

        let result = service.renderAnnotatedImage(
            baseImage: image,
            annotations: annotations,
            canvasSize: CGSize(width: 800, height: 600),
            imageRect: CGRect(x: 20, y: 20, width: 760, height: 560)
        )

        XCTAssertNotNil(result)
    }

    func testRenderAnnotatedImage_withArrow() {
        let service = ExportService()
        let image = makeTestImage()

        let annotations: [any AnnotationItem] = [
            ArrowAnnotation(startPoint: CGPoint(x: 50, y: 50),
                          endPoint: CGPoint(x: 200, y: 150),
                          color: .red, strokeWidth: 2, isCurved: false)
        ]

        let result = service.renderAnnotatedImage(
            baseImage: image,
            annotations: annotations,
            canvasSize: CGSize(width: 800, height: 600),
            imageRect: CGRect(x: 20, y: 20, width: 760, height: 560)
        )

        XCTAssertNotNil(result)
    }

    func testRenderAnnotatedImage_withText() {
        let service = ExportService()
        let image = makeTestImage()

        let annotations: [any AnnotationItem] = [
            TextAnnotation(position: CGPoint(x: 100, y: 100),
                         text: "Test Text",
                         font: .systemFont(ofSize: 16),
                         color: .red, backgroundColor: nil, style: .plain)
        ]

        let result = service.renderAnnotatedImage(
            baseImage: image,
            annotations: annotations,
            canvasSize: CGSize(width: 800, height: 600),
            imageRect: CGRect(x: 20, y: 20, width: 760, height: 560)
        )

        XCTAssertNotNil(result)
    }

    func testRenderAnnotatedImage_withCounter() {
        let service = ExportService()
        let image = makeTestImage()

        let annotations: [any AnnotationItem] = [
            CounterAnnotation(position: CGPoint(x: 100, y: 100),
                            number: 1, color: .red, size: 28)
        ]

        let result = service.renderAnnotatedImage(
            baseImage: image,
            annotations: annotations,
            canvasSize: CGSize(width: 800, height: 600),
            imageRect: CGRect(x: 20, y: 20, width: 760, height: 560)
        )

        XCTAssertNotNil(result)
    }

    func testRenderAnnotatedImage_withPencil() {
        let service = ExportService()
        let image = makeTestImage()

        let annotations: [any AnnotationItem] = [
            PencilAnnotation(
                points: [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 30), CGPoint(x: 100, y: 20)],
                color: .red, strokeWidth: 3, isSmoothed: true
            )
        ]

        let result = service.renderAnnotatedImage(
            baseImage: image,
            annotations: annotations,
            canvasSize: CGSize(width: 800, height: 600),
            imageRect: CGRect(x: 20, y: 20, width: 760, height: 560)
        )

        XCTAssertNotNil(result)
    }

    func testRenderAnnotatedImage_allAnnotationTypes() {
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

        let result = service.renderAnnotatedImage(
            baseImage: image,
            annotations: annotations,
            canvasSize: CGSize(width: 800, height: 600),
            imageRect: CGRect(x: 20, y: 20, width: 760, height: 560)
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.size, image.size)
    }
}
