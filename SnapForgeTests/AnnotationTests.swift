import AppKit
import SwiftUI
import Testing

@testable import SnapForge

/// Comprehensive tests for annotation state and tools
@MainActor
struct AnnotateStateTests {

  private func makeState() -> AnnotateState {
    AnnotateState()
  }

  private func makeRectAnnotation(
    x: CGFloat = 50, y: CGFloat = 50, w: CGFloat = 100, h: CGFloat = 100,
    color: Color = .red
  ) -> AnnotationItem {
    AnnotationItem(
      type: .rectangle,
      bounds: CGRect(x: x, y: y, width: w, height: h),
      properties: AnnotationProperties(strokeColor: color, strokeWidth: 2)
    )
  }

  private func makeArrowAnnotation(
    start: CGPoint = .zero, end: CGPoint = CGPoint(x: 100, y: 100),
    color: Color = .red
  ) -> AnnotationItem {
    AnnotationItem(
      type: .arrow(start: start, end: end),
      bounds: CGRect(
        x: min(start.x, end.x), y: min(start.y, end.y),
        width: abs(end.x - start.x), height: abs(end.y - start.y)
      ),
      properties: AnnotationProperties(strokeColor: color, strokeWidth: 2)
    )
  }

  // MARK: - Initial State

  @Test func initialState() {
    let state = makeState()
    #expect(state.selectedTool == .selection)
    #expect(state.strokeWidth == 3)
    #expect(state.annotations.isEmpty)
    #expect(state.canUndo == false)
    #expect(state.canRedo == false)
    #expect(state.cropRect == nil)
  }

  // MARK: - Undo / Redo

  @Test func undoRestoresPreviousState() {
    let state = makeState()
    state.saveState()
    state.annotations.append(makeRectAnnotation())
    #expect(state.annotations.count == 1)
    #expect(state.canUndo)

    state.undo()
    #expect(state.annotations.count == 0)
    #expect(state.canRedo)
  }

  @Test func redoRestoresUndoneState() {
    let state = makeState()
    state.saveState()
    state.annotations.append(makeRectAnnotation())
    state.undo()
    #expect(state.annotations.count == 0)

    state.redo()
    #expect(state.annotations.count == 1)
    #expect(state.canRedo == false)
  }

  @Test func addAnnotationClearsRedoStack() {
    let state = makeState()
    state.saveState()
    state.annotations.append(makeRectAnnotation())
    state.undo()
    #expect(state.canRedo)

    state.saveState()
    state.annotations.append(makeRectAnnotation(color: .blue))
    #expect(state.canRedo == false, "Adding new annotation should clear redo stack")
  }

  @Test func multipleUndoRedo() {
    let state = makeState()

    state.saveState()
    state.annotations.append(makeRectAnnotation())
    state.saveState()
    state.annotations.append(makeRectAnnotation(color: .blue))
    state.saveState()
    state.annotations.append(makeArrowAnnotation())

    #expect(state.annotations.count == 3)

    state.undo()
    #expect(state.annotations.count == 2)
    state.undo()
    #expect(state.annotations.count == 1)

    state.redo()
    #expect(state.annotations.count == 2)

    state.undo()
    state.undo()
    #expect(state.annotations.count == 0)
    #expect(state.canUndo == false)
  }

  @Test func undoWhenEmptyDoesNothing() {
    let state = makeState()
    state.undo()
    #expect(state.annotations.count == 0)
  }

  @Test func redoWhenEmptyDoesNothing() {
    let state = makeState()
    state.redo()
    #expect(state.annotations.count == 0)
  }

  // MARK: - Add Annotations

  @Test func addRectangleAnnotation() {
    let state = makeState()
    let rect = CGRect(x: 50, y: 50, width: 200, height: 100)
    state.saveState()
    state.annotations.append(
      AnnotationItem(
        type: .rectangle,
        bounds: rect,
        properties: AnnotationProperties(strokeColor: .red, strokeWidth: 3)
      )
    )

    #expect(state.annotations.count == 1)
    #expect(state.annotations[0].bounds == rect)
    if case .rectangle = state.annotations[0].type {} else {
      Issue.record("Expected .rectangle type")
    }
  }

  @Test func addFilledRectangleAnnotation() {
    let state = makeState()
    state.saveState()
    state.annotations.append(
      AnnotationItem(
        type: .filledRectangle,
        bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
        properties: AnnotationProperties(strokeColor: .blue, fillColor: .blue, strokeWidth: 2)
      )
    )

    if case .filledRectangle = state.annotations[0].type {} else {
      Issue.record("Expected .filledRectangle type")
    }
  }

  @Test func addOvalAnnotation() {
    let state = makeState()
    state.saveState()
    state.annotations.append(
      AnnotationItem(
        type: .oval,
        bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
        properties: AnnotationProperties(strokeColor: .blue, strokeWidth: 2)
      )
    )

    if case .oval = state.annotations[0].type {} else {
      Issue.record("Expected .oval type")
    }
  }

  @Test func addArrowAnnotation() {
    let state = makeState()
    let start = CGPoint(x: 10, y: 20)
    let end = CGPoint(x: 200, y: 150)
    state.saveState()
    state.annotations.append(makeArrowAnnotation(start: start, end: end))

    #expect(state.annotations.count == 1)
    if case .arrow(let s, let e) = state.annotations[0].type {
      #expect(s == start)
      #expect(e == end)
    } else {
      Issue.record("Expected .arrow type")
    }
  }

  @Test func addLineAnnotation() {
    let state = makeState()
    state.saveState()
    state.annotations.append(
      AnnotationItem(
        type: .line(start: .zero, end: CGPoint(x: 100, y: 0)),
        bounds: CGRect(x: 0, y: 0, width: 100, height: 0),
        properties: AnnotationProperties(strokeColor: .green, strokeWidth: 1)
      )
    )

    if case .line = state.annotations[0].type {} else {
      Issue.record("Expected .line type")
    }
  }

  @Test func addPencilAnnotation() {
    let state = makeState()
    let points: [CGPoint] = [
      CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 15),
      CGPoint(x: 30, y: 12), CGPoint(x: 40, y: 20), CGPoint(x: 50, y: 18),
    ]
    state.saveState()
    state.annotations.append(
      AnnotationItem(
        type: .path(points),
        bounds: CGRect(x: 10, y: 10, width: 40, height: 10),
        properties: AnnotationProperties(strokeColor: .red, strokeWidth: 2)
      )
    )

    if case .path(let pts) = state.annotations[0].type {
      #expect(pts.count == 5)
    } else {
      Issue.record("Expected .path type")
    }
  }

  @Test func addHighlighterAnnotation() {
    let state = makeState()
    let points = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 200, y: 0)]
    state.saveState()
    state.annotations.append(
      AnnotationItem(
        type: .highlight(points),
        bounds: CGRect(x: 0, y: 0, width: 200, height: 0),
        properties: AnnotationProperties(strokeColor: .yellow, strokeWidth: 12)
      )
    )

    if case .highlight(let pts) = state.annotations[0].type {
      #expect(pts.count == 3)
    } else {
      Issue.record("Expected .highlight type")
    }
  }

  @Test func addTextAnnotation() {
    let state = makeState()
    state.saveState()
    state.annotations.append(
      AnnotationItem(
        type: .text("Hello World"),
        bounds: CGRect(x: 100, y: 100, width: 100, height: 28),
        properties: AnnotationProperties(strokeColor: .red, fontSize: 16)
      )
    )

    if case .text(let content) = state.annotations[0].type {
      #expect(content == "Hello World")
    } else {
      Issue.record("Expected .text type")
    }
  }

  @Test func addCounterAnnotation() {
    let state = makeState()
    let num = state.nextCounterValue()
    state.saveState()
    state.annotations.append(
      AnnotationItem(
        type: .counter(num),
        bounds: CGRect(x: 200, y: 200, width: 24, height: 24),
        properties: AnnotationProperties(strokeColor: .red)
      )
    )

    if case .counter(let v) = state.annotations[0].type {
      #expect(v == 1)
    } else {
      Issue.record("Expected .counter type")
    }
  }

  @Test func counterAutoIncrement() {
    let state = makeState()
    #expect(state.nextCounterValue() == 1)

    state.saveState()
    state.annotations.append(
      AnnotationItem(
        type: .counter(1),
        bounds: CGRect(x: 0, y: 0, width: 24, height: 24),
        properties: AnnotationProperties(strokeColor: .red)
      )
    )
    #expect(state.nextCounterValue() == 2)

    state.saveState()
    state.annotations.append(
      AnnotationItem(
        type: .counter(2),
        bounds: CGRect(x: 50, y: 0, width: 24, height: 24),
        properties: AnnotationProperties(strokeColor: .red)
      )
    )
    #expect(state.nextCounterValue() == 3)
  }

  @Test func counterResetsOnClearAll() {
    let state = makeState()
    state.saveState()
    state.annotations.append(
      AnnotationItem(
        type: .counter(1),
        bounds: .zero,
        properties: AnnotationProperties(strokeColor: .red)
      )
    )
    state.clearAll()
    #expect(state.nextCounterValue() == 1)
  }

  @Test func addBlurAnnotation() {
    let state = makeState()
    state.saveState()
    state.annotations.append(
      AnnotationItem(
        type: .blur(.pixelated),
        bounds: CGRect(x: 50, y: 50, width: 100, height: 60),
        properties: AnnotationProperties()
      )
    )

    if case .blur(let blurType) = state.annotations[0].type {
      #expect(blurType == .pixelated)
    } else {
      Issue.record("Expected .blur type")
    }
  }

  @Test func addGaussianBlurAnnotation() {
    let state = makeState()
    state.saveState()
    state.annotations.append(
      AnnotationItem(
        type: .blur(.gaussian),
        bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
        properties: AnnotationProperties()
      )
    )

    if case .blur(let blurType) = state.annotations[0].type {
      #expect(blurType == .gaussian)
    } else {
      Issue.record("Expected .blur(.gaussian) type")
    }
  }

  // MARK: - Delete Annotation

  @Test func deleteSelectedAnnotation() {
    let state = makeState()
    let annotation = makeRectAnnotation()
    state.saveState()
    state.annotations.append(annotation)
    state.selectedAnnotationId = annotation.id
    #expect(state.annotations.count == 1)

    state.deleteSelectedAnnotation()
    #expect(state.annotations.count == 0)
  }

  @Test func deleteWithNoSelectionDoesNothing() {
    let state = makeState()
    state.saveState()
    state.annotations.append(makeRectAnnotation())
    state.deleteSelectedAnnotation()
    #expect(state.annotations.count == 1)
  }

  // MARK: - Clear All

  @Test func clearAllRemovesAllAnnotations() {
    let state = makeState()
    state.saveState()
    state.annotations.append(makeRectAnnotation())
    state.saveState()
    state.annotations.append(makeArrowAnnotation())
    state.clearAll()
    #expect(state.annotations.isEmpty)
    #expect(state.canUndo, "Should be undoable")
  }

  @Test func clearAllWhenEmptyDoesNotAddUndoState() {
    let state = makeState()
    state.clearAll()
    #expect(state.canUndo == false, "Empty clearAll should not add undo state")
  }

  // MARK: - Text Update

  @Test func updateTextChangesTextContent() {
    let state = makeState()
    let textAnnotation = AnnotationItem(
      type: .text("Original"),
      bounds: CGRect(x: 100, y: 100, width: 100, height: 28),
      properties: AnnotationProperties(strokeColor: .red, fontSize: 14)
    )
    state.saveState()
    state.annotations.append(textAnnotation)

    state.updateAnnotationText(id: textAnnotation.id, text: "Updated Text")

    if case .text(let content) = state.annotations[0].type {
      #expect(content == "Updated Text")
    } else {
      Issue.record("Expected .text type")
    }
  }

  @Test func updateTextNonexistentIDDoesNothing() {
    let state = makeState()
    state.saveState()
    state.annotations.append(
      AnnotationItem(
        type: .text("Test"),
        bounds: CGRect(x: 0, y: 0, width: 100, height: 28),
        properties: AnnotationProperties(strokeColor: .red, fontSize: 14)
      )
    )
    state.updateAnnotationText(id: UUID(), text: "Nope")

    if case .text(let content) = state.annotations[0].type {
      #expect(content == "Test")
    } else {
      Issue.record("Expected .text type")
    }
  }

  // MARK: - Selection / Hit Testing

  @Test func selectAnnotationShape() {
    let state = makeState()
    state.saveState()
    state.annotations.append(makeRectAnnotation())
    let hit = state.selectAnnotation(at: CGPoint(x: 75, y: 75))
    #expect(hit != nil)
    #expect(state.selectedAnnotationId != nil)
  }

  @Test func selectAnnotationMissedClickDeselectsAll() {
    let state = makeState()
    state.saveState()
    state.annotations.append(makeRectAnnotation())
    state.selectedAnnotationId = state.annotations[0].id
    let hit = state.selectAnnotation(at: CGPoint(x: 500, y: 500))
    #expect(hit == nil)
    #expect(state.selectedAnnotationId == nil)
  }

  @Test func selectAnnotationArrow() {
    let state = makeState()
    let arrow = makeArrowAnnotation()
    state.saveState()
    state.annotations.append(arrow)
    let hit = state.selectAnnotation(at: CGPoint(x: 50, y: 50))
    #expect(hit != nil)
  }

  @Test func selectAnnotationCounter() {
    let state = makeState()
    state.saveState()
    state.annotations.append(
      AnnotationItem(
        type: .counter(1),
        bounds: CGRect(x: 88, y: 88, width: 24, height: 24),
        properties: AnnotationProperties(strokeColor: .red)
      )
    )
    let hit = state.selectAnnotation(at: CGPoint(x: 100, y: 100))
    #expect(hit != nil)
  }

  @Test func selectAnnotationTopmostWins() {
    let state = makeState()
    state.saveState()
    state.annotations.append(makeRectAnnotation(x: 0, y: 0, w: 200, h: 200, color: .red))
    state.saveState()
    state.annotations.append(makeRectAnnotation(x: 50, y: 50, w: 100, h: 100, color: .blue))

    let hit = state.selectAnnotation(at: CGPoint(x: 75, y: 75))
    #expect(hit?.id == state.annotations[1].id, "Top shape SHOULD be selected")
  }

  // MARK: - Crop Rect

  @Test func cropRectCanBeSet() {
    let state = makeState()
    let rect = CGRect(x: 10, y: 10, width: 200, height: 150)
    state.cropRect = rect
    #expect(state.cropRect == rect)
  }

  @Test func cropRectPreservesDimensions() {
    let state = makeState()
    let rect = CGRect(x: 100, y: 100, width: 400, height: 300)
    state.cropRect = rect
    #expect(state.cropRect?.width == 400)
    #expect(state.cropRect?.height == 300)
    #expect(state.cropRect?.origin == CGPoint(x: 100, y: 100))
  }

  @Test func clearAllDoesNotAffectCropRect() {
    let state = makeState()
    let rect = CGRect(x: 10, y: 10, width: 200, height: 150)
    state.cropRect = rect
    state.saveState()
    state.annotations.append(makeRectAnnotation())
    state.clearAll()
    #expect(state.cropRect == rect, "Crop rect should survive clearAll")
  }

  // MARK: - Nudge

  @Test func nudgeMovesAnnotation() {
    let state = makeState()
    let annotation = makeRectAnnotation(x: 100, y: 100, w: 50, h: 50)
    state.saveState()
    state.annotations.append(annotation)
    state.selectedAnnotationId = annotation.id

    state.nudgeSelectedAnnotation(dx: 10, dy: 20)

    #expect(state.annotations[0].bounds.origin.x == 110)
    #expect(state.annotations[0].bounds.origin.y == 120)
  }

  @Test func nudgeWithNoSelectionDoesNothing() {
    let state = makeState()
    state.saveState()
    state.annotations.append(makeRectAnnotation())
    state.nudgeSelectedAnnotation(dx: 10, dy: 10)
    #expect(state.annotations[0].bounds.origin.x == 50)
  }

  // MARK: - Update Bounds

  @Test func updateBoundsUpdatesPosition() {
    let state = makeState()
    let annotation = makeRectAnnotation()
    state.saveState()
    state.annotations.append(annotation)

    let newBounds = CGRect(x: 200, y: 200, width: 100, height: 100)
    state.updateAnnotationBounds(id: annotation.id, bounds: newBounds)

    #expect(state.annotations[0].bounds == newBounds)
  }

  @Test func updateBoundsUpdatesArrowPoints() {
    let state = makeState()
    let start = CGPoint(x: 50, y: 50)
    let end = CGPoint(x: 150, y: 150)
    let arrow = makeArrowAnnotation(start: start, end: end)
    state.saveState()
    state.annotations.append(arrow)

    let newBounds = CGRect(x: 100, y: 100, width: 100, height: 100)
    state.updateAnnotationBounds(id: arrow.id, bounds: newBounds)

    if case .arrow(let newStart, let newEnd) = state.annotations[0].type {
      #expect(newStart.x == 100)
      #expect(newStart.y == 100)
      #expect(newEnd.x == 200)
      #expect(newEnd.y == 200)
    } else {
      Issue.record("Expected .arrow type")
    }
  }

  // MARK: - Properties Update

  @Test func updateAnnotationStrokeWidth() {
    let state = makeState()
    let annotation = makeRectAnnotation()
    state.saveState()
    state.annotations.append(annotation)

    state.updateAnnotationProperties(id: annotation.id, strokeWidth: 8)
    #expect(state.annotations[0].properties.strokeWidth == 8)
  }

  @Test func updateAnnotationStrokeColor() {
    let state = makeState()
    let annotation = makeRectAnnotation()
    state.saveState()
    state.annotations.append(annotation)

    state.updateAnnotationProperties(id: annotation.id, strokeColor: .blue)
    #expect(state.annotations[0].properties.strokeColor == .blue)
  }
}

// MARK: - Annotation Tool Type Tests

struct AnnotationToolTypeTests {

  @Test(arguments: AnnotationToolType.allCases)
  func toolHasIconAndDisplayName(tool: AnnotationToolType) {
    #expect(tool.icon.isEmpty == false, "\(tool.rawValue) should have an icon")
    #expect(tool.displayName.isEmpty == false)
  }

  @Test func allCasesCount() {
    #expect(AnnotationToolType.allCases.count == 13)
  }

  @Test func identifiersAreUnique() {
    let ids = AnnotationToolType.allCases.map { $0.id }
    let uniqueIds = Set(ids)
    #expect(ids.count == uniqueIds.count, "All tool IDs should be unique")
  }
}

// MARK: - Annotation Item Model Tests

struct AnnotationItemModelTests {

  @Test func annotationHasUniqueID() {
    let a = AnnotationItem(type: .rectangle, bounds: .zero, properties: AnnotationProperties())
    let b = AnnotationItem(type: .rectangle, bounds: .zero, properties: AnnotationProperties())
    #expect(a.id != b.id)
  }

  @Test func hitTestRectangle() {
    let item = AnnotationItem(
      type: .rectangle,
      bounds: CGRect(x: 50, y: 50, width: 100, height: 100),
      properties: AnnotationProperties()
    )
    #expect(item.containsPoint(CGPoint(x: 75, y: 75)))
    #expect(!item.containsPoint(CGPoint(x: 0, y: 0)))
  }

  @Test func hitTestOval() {
    let item = AnnotationItem(
      type: .oval,
      bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      properties: AnnotationProperties()
    )
    #expect(item.containsPoint(CGPoint(x: 50, y: 50)))
    #expect(!item.containsPoint(CGPoint(x: 0, y: 0)))
  }

  @Test func hitTestArrow() {
    let item = AnnotationItem(
      type: .arrow(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100)),
      bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      properties: AnnotationProperties(strokeWidth: 2)
    )
    #expect(item.containsPoint(CGPoint(x: 50, y: 50)))
    #expect(!item.containsPoint(CGPoint(x: 0, y: 100)))
  }

  @Test func hitTestCounter() {
    let item = AnnotationItem(
      type: .counter(1),
      bounds: CGRect(x: 88, y: 88, width: 24, height: 24),
      properties: AnnotationProperties(strokeColor: .red)
    )
    #expect(item.containsPoint(CGPoint(x: 100, y: 100)))
    #expect(!item.containsPoint(CGPoint(x: 200, y: 200)))
  }
}

// MARK: - Export Service Tests

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
    let result = try #require(
      service.renderAnnotatedImage(
        baseImage: image, annotations: [],
        imageSize: image.size
      ))
    #expect(result.size == image.size)
  }

  @Test func renderAnnotatedImageWithShape() {
    let service = ExportService()
    let image = makeTestImage()
    let annotations: [AnnotationItem] = [
      AnnotationItem(
        type: .rectangle,
        bounds: CGRect(x: 50, y: 50, width: 100, height: 80),
        properties: AnnotationProperties(strokeColor: .red, strokeWidth: 3)
      )
    ]
    let result = service.renderAnnotatedImage(
      baseImage: image, annotations: annotations,
      imageSize: image.size
    )
    #expect(result != nil)
  }

  @Test func renderAnnotatedImageWithArrow() {
    let service = ExportService()
    let image = makeTestImage()
    let annotations: [AnnotationItem] = [
      AnnotationItem(
        type: .arrow(start: CGPoint(x: 50, y: 50), end: CGPoint(x: 200, y: 150)),
        bounds: CGRect(x: 50, y: 50, width: 150, height: 100),
        properties: AnnotationProperties(strokeColor: .red, strokeWidth: 2)
      )
    ]
    let result = service.renderAnnotatedImage(
      baseImage: image, annotations: annotations,
      imageSize: image.size
    )
    #expect(result != nil)
  }

  @Test func renderAnnotatedImageWithText() {
    let service = ExportService()
    let image = makeTestImage()
    let annotations: [AnnotationItem] = [
      AnnotationItem(
        type: .text("Test Text"),
        bounds: CGRect(x: 100, y: 100, width: 100, height: 28),
        properties: AnnotationProperties(strokeColor: .red, fontSize: 16)
      )
    ]
    let result = service.renderAnnotatedImage(
      baseImage: image, annotations: annotations,
      imageSize: image.size
    )
    #expect(result != nil)
  }

  @Test func renderAnnotatedImageWithCounter() {
    let service = ExportService()
    let image = makeTestImage()
    let annotations: [AnnotationItem] = [
      AnnotationItem(
        type: .counter(1),
        bounds: CGRect(x: 88, y: 88, width: 24, height: 24),
        properties: AnnotationProperties(strokeColor: .red)
      )
    ]
    let result = service.renderAnnotatedImage(
      baseImage: image, annotations: annotations,
      imageSize: image.size
    )
    #expect(result != nil)
  }

  @Test func renderAnnotatedImageWithPencil() {
    let service = ExportService()
    let image = makeTestImage()
    let annotations: [AnnotationItem] = [
      AnnotationItem(
        type: .path([CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 30), CGPoint(x: 100, y: 20)]),
        bounds: CGRect(x: 10, y: 10, width: 90, height: 20),
        properties: AnnotationProperties(strokeColor: .red, strokeWidth: 3)
      )
    ]
    let result = service.renderAnnotatedImage(
      baseImage: image, annotations: annotations,
      imageSize: image.size
    )
    #expect(result != nil)
  }

  @Test func renderAnnotatedImageAllAnnotationTypes() throws {
    let service = ExportService()
    let image = makeTestImage()
    let annotations: [AnnotationItem] = [
      AnnotationItem(type: .rectangle, bounds: CGRect(x: 10, y: 10, width: 80, height: 60), properties: AnnotationProperties(strokeColor: .red, strokeWidth: 2)),
      AnnotationItem(type: .oval, bounds: CGRect(x: 100, y: 10, width: 60, height: 60), properties: AnnotationProperties(strokeColor: .blue, strokeWidth: 2)),
      AnnotationItem(type: .arrow(start: CGPoint(x: 200, y: 50), end: CGPoint(x: 300, y: 100)), bounds: CGRect(x: 200, y: 50, width: 100, height: 50), properties: AnnotationProperties(strokeColor: .green, strokeWidth: 2)),
      AnnotationItem(type: .line(start: CGPoint(x: 10, y: 200), end: CGPoint(x: 100, y: 200)), bounds: CGRect(x: 10, y: 200, width: 90, height: 0), properties: AnnotationProperties(strokeColor: .orange, strokeWidth: 1)),
      AnnotationItem(type: .path([CGPoint(x: 10, y: 150), CGPoint(x: 50, y: 130), CGPoint(x: 100, y: 160)]), bounds: CGRect(x: 10, y: 130, width: 90, height: 30), properties: AnnotationProperties(strokeColor: .purple, strokeWidth: 2)),
      AnnotationItem(type: .text("Test"), bounds: CGRect(x: 200, y: 200, width: 60, height: 28), properties: AnnotationProperties(strokeColor: .red, fontSize: 14)),
      AnnotationItem(type: .counter(1), bounds: CGRect(x: 338, y: 38, width: 24, height: 24), properties: AnnotationProperties(strokeColor: .red)),
    ]
    let result = try #require(
      service.renderAnnotatedImage(
        baseImage: image, annotations: annotations,
        imageSize: image.size
      ))
    #expect(result.size == image.size)
  }

  @Test func renderAnnotatedImageWithBlur() {
    let service = ExportService()
    let image = makeTestImage()
    let annotations: [AnnotationItem] = [
      AnnotationItem(
        type: .blur(.pixelated),
        bounds: CGRect(x: 10, y: 10, width: 50, height: 50),
        properties: AnnotationProperties()
      )
    ]
    let result = service.renderAnnotatedImage(
      baseImage: image, annotations: annotations,
      imageSize: image.size
    )
    #expect(result != nil, "Rendering blur should not crash")
  }

  @Test func renderAnnotatedImageWithHighlighter() {
    let service = ExportService()
    let image = makeTestImage()
    let annotations: [AnnotationItem] = [
      AnnotationItem(
        type: .highlight([CGPoint(x: 10, y: 50), CGPoint(x: 100, y: 50), CGPoint(x: 200, y: 50)]),
        bounds: CGRect(x: 10, y: 50, width: 190, height: 0),
        properties: AnnotationProperties(strokeColor: .yellow, strokeWidth: 12)
      )
    ]
    let result = service.renderAnnotatedImage(
      baseImage: image, annotations: annotations,
      imageSize: image.size
    )
    #expect(result != nil)
  }
}

// MARK: - Multi-Tool Workflow Integration Tests

@MainActor
struct AnnotationWorkflowTests {

  @Test func completeWorkflowAddMultipleTypesUndoAllRedoAll() {
    let state = AnnotateState()

    state.saveState()
    state.annotations.append(AnnotationItem(type: .rectangle, bounds: CGRect(x: 10, y: 10, width: 100, height: 50), properties: AnnotationProperties(strokeColor: .red)))
    state.saveState()
    state.annotations.append(AnnotationItem(type: .arrow(start: CGPoint(x: 200, y: 50), end: CGPoint(x: 300, y: 150)), bounds: CGRect(x: 200, y: 50, width: 100, height: 100), properties: AnnotationProperties(strokeColor: .blue)))
    state.saveState()
    state.annotations.append(AnnotationItem(type: .text("Hello"), bounds: CGRect(x: 100, y: 200, width: 100, height: 28), properties: AnnotationProperties(strokeColor: .green, fontSize: 16)))
    state.saveState()
    state.annotations.append(AnnotationItem(type: .counter(state.nextCounterValue()), bounds: CGRect(x: 338, y: 38, width: 24, height: 24), properties: AnnotationProperties(strokeColor: .red)))
    state.saveState()
    state.annotations.append(AnnotationItem(type: .path([CGPoint(x: 10, y: 300), CGPoint(x: 50, y: 280), CGPoint(x: 100, y: 310)]), bounds: CGRect(x: 10, y: 280, width: 90, height: 30), properties: AnnotationProperties(strokeColor: .purple)))

    #expect(state.annotations.count == 5)

    state.undo(); state.undo(); state.undo(); state.undo(); state.undo()
    #expect(state.annotations.count == 0)
    #expect(state.canUndo == false)
    #expect(state.canRedo)

    state.redo(); state.redo(); state.redo(); state.redo(); state.redo()
    #expect(state.annotations.count == 5)
    #expect(state.canUndo)
    #expect(state.canRedo == false)
  }

  @Test func selectAndDeleteWorkflow() {
    let state = AnnotateState()
    let shape = AnnotationItem(type: .rectangle, bounds: CGRect(x: 50, y: 50, width: 100, height: 100), properties: AnnotationProperties(strokeColor: .red))
    state.saveState()
    state.annotations.append(shape)
    state.saveState()
    state.annotations.append(AnnotationItem(type: .arrow(start: CGPoint(x: 250, y: 250), end: CGPoint(x: 350, y: 350)), bounds: CGRect(x: 250, y: 250, width: 100, height: 100), properties: AnnotationProperties(strokeColor: .blue)))

    let hit = state.selectAnnotation(at: CGPoint(x: 75, y: 75))
    #expect(hit?.id == shape.id)
    #expect(state.selectedAnnotationId == shape.id)

    state.deleteSelectedAnnotation()
    #expect(state.annotations.count == 1)
  }

  @Test func textEditAndUndoWorkflow() {
    let state = AnnotateState()
    let textAnnotation = AnnotationItem(
      type: .text("Initial"),
      bounds: CGRect(x: 100, y: 100, width: 100, height: 28),
      properties: AnnotationProperties(strokeColor: .red, fontSize: 14)
    )
    state.saveState()
    state.annotations.append(textAnnotation)

    state.updateAnnotationText(id: textAnnotation.id, text: "Updated")
    if case .text(let content) = state.annotations[0].type {
      #expect(content == "Updated")
    }

    state.undo()
    #expect(state.annotations.count == 0)
  }
}

// MARK: - Layer Management Tests

@MainActor
struct LayerManagementTests {

  private func makeState() -> AnnotateState {
    AnnotateState()
  }

  private func makeRectAnnotation(
    x: CGFloat = 50, y: CGFloat = 50, w: CGFloat = 100, h: CGFloat = 100,
    color: Color = .red
  ) -> AnnotationItem {
    AnnotationItem(
      type: .rectangle,
      bounds: CGRect(x: x, y: y, width: w, height: h),
      properties: AnnotationProperties(strokeColor: color, strokeWidth: 2)
    )
  }

  // MARK: - Visibility Toggle

  @Test func toggleVisibilityHidesAnnotation() {
    let state = makeState()
    let annotation = makeRectAnnotation()
    state.annotations.append(annotation)
    #expect(state.isAnnotationVisible(annotation.id))

    state.toggleVisibility(id: annotation.id)
    #expect(!state.isAnnotationVisible(annotation.id))
    #expect(state.hiddenAnnotationIds.contains(annotation.id))
  }

  @Test func toggleVisibilityShowsAnnotation() {
    let state = makeState()
    let annotation = makeRectAnnotation()
    state.annotations.append(annotation)

    state.toggleVisibility(id: annotation.id) // hide
    state.toggleVisibility(id: annotation.id) // show
    #expect(state.isAnnotationVisible(annotation.id))
    #expect(!state.hiddenAnnotationIds.contains(annotation.id))
  }

  @Test func hidingSelectedAnnotationDeselectsIt() {
    let state = makeState()
    let annotation = makeRectAnnotation()
    state.annotations.append(annotation)
    state.selectedAnnotationId = annotation.id

    state.toggleVisibility(id: annotation.id)
    #expect(state.selectedAnnotationId == nil)
  }

  // MARK: - Lock Toggle

  @Test func toggleLockLocksAnnotation() {
    let state = makeState()
    let annotation = makeRectAnnotation()
    state.annotations.append(annotation)
    #expect(!state.isAnnotationLocked(annotation.id))

    state.toggleLock(id: annotation.id)
    #expect(state.isAnnotationLocked(annotation.id))
    #expect(state.lockedAnnotationIds.contains(annotation.id))
  }

  @Test func toggleLockUnlocksAnnotation() {
    let state = makeState()
    let annotation = makeRectAnnotation()
    state.annotations.append(annotation)

    state.toggleLock(id: annotation.id) // lock
    state.toggleLock(id: annotation.id) // unlock
    #expect(!state.isAnnotationLocked(annotation.id))
  }

  @Test func lockingSelectedAnnotationDeselectsIt() {
    let state = makeState()
    let annotation = makeRectAnnotation()
    state.annotations.append(annotation)
    state.selectedAnnotationId = annotation.id

    state.toggleLock(id: annotation.id)
    #expect(state.selectedAnnotationId == nil)
  }

  // MARK: - Select Annotation Skips Hidden/Locked

  @Test func selectAnnotationSkipsHiddenAnnotation() {
    let state = makeState()
    let annotation = makeRectAnnotation(x: 50, y: 50, w: 100, h: 100)
    state.annotations.append(annotation)

    state.toggleVisibility(id: annotation.id)
    let hit = state.selectAnnotation(at: CGPoint(x: 75, y: 75))
    #expect(hit == nil)
    #expect(state.selectedAnnotationId == nil)
  }

  @Test func selectAnnotationSkipsLockedAnnotation() {
    let state = makeState()
    let annotation = makeRectAnnotation(x: 50, y: 50, w: 100, h: 100)
    state.annotations.append(annotation)

    state.toggleLock(id: annotation.id)
    let hit = state.selectAnnotation(at: CGPoint(x: 75, y: 75))
    #expect(hit == nil)
    #expect(state.selectedAnnotationId == nil)
  }

  @Test func selectAnnotationSkipsHiddenButSelectsVisibleBelow() {
    let state = makeState()
    let bottom = makeRectAnnotation(x: 0, y: 0, w: 200, h: 200, color: .red)
    let top = makeRectAnnotation(x: 50, y: 50, w: 100, h: 100, color: .blue)
    state.annotations.append(bottom)
    state.annotations.append(top)

    // Hide the top annotation
    state.toggleVisibility(id: top.id)

    // Click should now select the bottom one
    let hit = state.selectAnnotation(at: CGPoint(x: 75, y: 75))
    #expect(hit?.id == bottom.id)
  }

  // MARK: - Move Annotation

  @Test func moveAnnotationReordersCorrectly() {
    let state = makeState()
    let first = makeRectAnnotation(color: .red)
    let second = makeRectAnnotation(color: .blue)
    let third = makeRectAnnotation(color: .green)
    state.annotations = [first, second, third]

    // Move first to end
    state.moveAnnotation(from: IndexSet(integer: 0), to: 3)
    #expect(state.annotations[0].id == second.id)
    #expect(state.annotations[1].id == third.id)
    #expect(state.annotations[2].id == first.id)
  }

  @Test func moveAnnotationSavesUndoState() {
    let state = makeState()
    let first = makeRectAnnotation(color: .red)
    let second = makeRectAnnotation(color: .blue)
    state.annotations = [first, second]

    state.moveAnnotation(from: IndexSet(integer: 0), to: 2)
    #expect(state.canUndo)
  }

  // MARK: - Clear All Resets Layer State

  @Test func clearAllResetsHiddenAndLockedSets() {
    let state = makeState()
    let annotation = makeRectAnnotation()
    state.saveState()
    state.annotations.append(annotation)

    state.toggleVisibility(id: annotation.id)
    state.toggleLock(id: annotation.id)
    #expect(!state.hiddenAnnotationIds.isEmpty)
    #expect(!state.lockedAnnotationIds.isEmpty)

    state.clearAll()
    #expect(state.hiddenAnnotationIds.isEmpty)
    #expect(state.lockedAnnotationIds.isEmpty)
  }

  // MARK: - Layers Panel Toggle

  @Test func layersPanelStartsHidden() {
    let state = makeState()
    #expect(state.isLayersPanelVisible == false)
  }

  @Test func layersPanelToggle() {
    let state = makeState()
    state.isLayersPanelVisible = true
    #expect(state.isLayersPanelVisible == true)
    state.isLayersPanelVisible = false
    #expect(state.isLayersPanelVisible == false)
  }
}

// MARK: - Annotation Type Display Name Tests

struct AnnotationTypeDisplayNameTests {

  @Test func rectangleDisplayName() {
    let type: AnnotationType = .rectangle
    #expect(type.displayName == "Rectangle")
  }

  @Test func textDisplayNameShowsPreview() {
    let type: AnnotationType = .text("Hello World")
    #expect(type.displayName == "Text: Hello World")
  }

  @Test func textDisplayNameTruncatesLongText() {
    let type: AnnotationType = .text("This is a very long text annotation content that should be truncated")
    #expect(type.displayName.starts(with: "Text: This is a very lon"))
  }

  @Test func counterDisplayNameShowsNumber() {
    let type: AnnotationType = .counter(5)
    #expect(type.displayName == "Counter #5")
  }

  @Test func blurDisplayNameShowsType() {
    let type: AnnotationType = .blur(.pixelated)
    #expect(type.displayName == "Blur (Pixelated)")
  }

  @Test func allTypesHaveIcons() {
    let types: [AnnotationType] = [
      .path([]), .rectangle, .filledRectangle, .oval,
      .arrow(start: .zero, end: .zero), .line(start: .zero, end: .zero),
      .text(""), .highlight([]), .blur(.gaussian), .counter(1),
    ]
    for type in types {
      #expect(!type.icon.isEmpty, "\(type.displayName) should have an icon")
    }
  }
}
