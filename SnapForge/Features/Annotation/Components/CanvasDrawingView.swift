import AppKit
import SwiftUI

/// NSViewRepresentable wrapper for the drawing canvas
struct CanvasDrawingView: NSViewRepresentable {
  @ObservedObject var state: AnnotateState
  var displayScale: CGFloat = 1.0

  func makeNSView(context: Context) -> DrawingCanvasNSView {
    let view = DrawingCanvasNSView(state: state)
    view.displayScale = displayScale
    return view
  }

  func updateNSView(_ nsView: DrawingCanvasNSView, context: Context) {
    nsView.state = state
    nsView.displayScale = displayScale
    nsView.needsDisplay = true
  }
}

/// Handle types for resize operations
enum ResizeHandle: Equatable {
  case topLeft, topRight, bottomLeft, bottomRight
  case top, bottom, left, right
}

/// Handle types for crop operations
enum CropHandle: String, CaseIterable {
  case topLeft, top, topRight
  case left, right
  case bottomLeft, bottom, bottomRight
  case body

  static var corners: [CropHandle] {
    [.topLeft, .topRight, .bottomLeft, .bottomRight]
  }

  static var edges: [CropHandle] {
    [.top, .bottom, .left, .right]
  }
}

/// NSView subclass handling mouse events and drawing
final class DrawingCanvasNSView: NSView {
  var state: AnnotateState
  var displayScale: CGFloat = 1.0
  private var currentPath: [CGPoint] = []
  private var isDrawing = false
  private var dragStart: CGPoint?

  // Selection and manipulation state
  private var isDraggingAnnotation = false
  private var isResizingAnnotation = false
  private var activeResizeHandle: ResizeHandle?
  private var dragOffset: CGPoint = .zero
  private var originalBounds: CGRect = .zero

  // Crop interaction state
  private var isCropDragging = false
  private var isCropResizing = false
  private var activeCropHandle: CropHandle?
  private var originalCropRect: CGRect = .zero

  private let handleSize: CGFloat = 8

  // Blur cache manager for performance optimization
  private let blurCacheManager = BlurCacheManager()

  init(state: AnnotateState) {
    self.state = state
    super.init(frame: .zero)
    setupView()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupView() {
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor

    let trackingArea = NSTrackingArea(
      rect: .zero,
      options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(trackingArea)
  }

  // MARK: - First Responder

  override var acceptsFirstResponder: Bool { true }

  /// Allow clicks to pass through without requiring window activation first
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func keyDown(with event: NSEvent) {
    let shift = event.modifierFlags.contains(.shift)
    let nudgeAmount: CGFloat = shift ? 10 : 1

    switch event.keyCode {
    case 51, 117: // Delete, Forward Delete
      if state.selectedAnnotationId != nil && state.editingTextAnnotationId == nil {
        Task { @MainActor in
          state.deleteSelectedAnnotation()
        }
        needsDisplay = true
      }

    case 53: // Escape
      if state.selectedTool == .crop && state.isCropActive {
        Task { @MainActor in
          state.cancelCrop()
        }
        needsDisplay = true
        return
      }
      Task { @MainActor in
        state.deselectAnnotation()
      }
      needsDisplay = true

    case 36: // Enter — confirm crop
      if state.selectedTool == .crop && state.isCropActive {
        Task { @MainActor in
          state.applyCrop()
          state.selectedTool = .selection
        }
        needsDisplay = true
        return
      }

    case 126: // Arrow Up
      if state.selectedAnnotationId != nil && state.editingTextAnnotationId == nil {
        Task { @MainActor in
          state.nudgeSelectedAnnotation(dx: 0, dy: nudgeAmount)
        }
        needsDisplay = true
      }

    case 125: // Arrow Down
      if state.selectedAnnotationId != nil && state.editingTextAnnotationId == nil {
        Task { @MainActor in
          state.nudgeSelectedAnnotation(dx: 0, dy: -nudgeAmount)
        }
        needsDisplay = true
      }

    case 123: // Arrow Left
      if state.selectedAnnotationId != nil && state.editingTextAnnotationId == nil {
        Task { @MainActor in
          state.nudgeSelectedAnnotation(dx: -nudgeAmount, dy: 0)
        }
        needsDisplay = true
      }

    case 124: // Arrow Right
      if state.selectedAnnotationId != nil && state.editingTextAnnotationId == nil {
        Task { @MainActor in
          state.nudgeSelectedAnnotation(dx: nudgeAmount, dy: 0)
        }
        needsDisplay = true
      }

    case 6: // Z key — Undo/Redo
      if event.modifierFlags.contains(.command) {
        Task { @MainActor in
          if event.modifierFlags.contains(.shift) {
            state.redo()
          } else {
            state.undo()
          }
        }
        needsDisplay = true
      }

    default:
      // Tool shortcuts
      if state.editingTextAnnotationId == nil,
         !event.modifierFlags.contains(.command),
         let char = event.characters?.lowercased().first
      {
        let matchedTool = AnnotationToolType.allCases.first { $0.defaultShortcut == char }
        if let tool = matchedTool {
          Task { @MainActor in
            state.selectedTool = tool
          }
          needsDisplay = true
        } else {
          super.keyDown(with: event)
        }
      } else {
        super.keyDown(with: event)
      }
    }
  }

  // MARK: - Hit Testing

  private func hitTestAnnotation(at point: CGPoint) -> AnnotationItem? {
    for annotation in state.annotations.reversed() {
      let expandedBounds = annotation.bounds.insetBy(dx: -10, dy: -10)
      guard expandedBounds.contains(point) else { continue }

      if annotation.containsPoint(point) {
        return annotation
      }
    }
    return nil
  }

  private func hitTestHandle(at point: CGPoint, for bounds: CGRect) -> ResizeHandle? {
    let handles: [(ResizeHandle, CGRect)] = [
      (.topLeft, handleRect(at: CGPoint(x: bounds.minX, y: bounds.maxY))),
      (.topRight, handleRect(at: CGPoint(x: bounds.maxX, y: bounds.maxY))),
      (.bottomLeft, handleRect(at: CGPoint(x: bounds.minX, y: bounds.minY))),
      (.bottomRight, handleRect(at: CGPoint(x: bounds.maxX, y: bounds.minY))),
    ]

    for (handle, rect) in handles {
      if rect.contains(point) {
        return handle
      }
    }
    return nil
  }

  private func handleRect(at center: CGPoint) -> CGRect {
    let displayHandleSize = handleSize / displayScale
    return CGRect(
      x: center.x - displayHandleSize / 2,
      y: center.y - displayHandleSize / 2,
      width: displayHandleSize,
      height: displayHandleSize
    )
  }

  // MARK: - Coordinate Transformation

  private func displayToImage(_ point: CGPoint) -> CGPoint {
    guard displayScale > 0 else { return point }
    return CGPoint(
      x: point.x / displayScale,
      y: point.y / displayScale
    )
  }

  private func imageToDisplay(_ point: CGPoint) -> CGPoint {
    CGPoint(
      x: point.x * displayScale,
      y: point.y * displayScale
    )
  }

  private func imageToDisplay(_ rect: CGRect) -> CGRect {
    CGRect(
      x: rect.origin.x * displayScale,
      y: rect.origin.y * displayScale,
      width: rect.width * displayScale,
      height: rect.height * displayScale
    )
  }

  /// Clamp point to effective drawing bounds
  private func clampToImageBounds(_ point: CGPoint) -> CGPoint {
    let bounds: CGRect
    if let cropRect = state.cropRect, !state.isCropActive {
      bounds = cropRect
    } else {
      bounds = CGRect(origin: .zero, size: CGSize(width: state.imageWidth, height: state.imageHeight))
    }

    return CGPoint(
      x: max(bounds.minX, min(point.x, bounds.maxX)),
      y: max(bounds.minY, min(point.y, bounds.maxY))
    )
  }

  // MARK: - Mouse Events

  override func mouseDown(with event: NSEvent) {
    let displayPoint = convert(event.locationInWindow, from: nil)
    let rawImagePoint = displayToImage(displayPoint)
    let imagePoint = clampToImageBounds(rawImagePoint)
    dragStart = imagePoint

    // Double-click on text to edit
    if event.clickCount == 2 {
      if let annotation = hitTestAnnotation(at: imagePoint),
         case .text = annotation.type
      {
        Task { @MainActor in
          state.editingTextAnnotationId = annotation.id
          state.selectedAnnotationId = annotation.id
        }
        needsDisplay = true
        return
      }
    }

    // Clear text editing when clicking elsewhere
    if state.editingTextAnnotationId != nil {
      Task { @MainActor in
        state.editingTextAnnotationId = nil
      }
    }

    // Check resize handles on selected annotation
    if let selectedId = state.selectedAnnotationId,
       let annotation = state.annotations.first(where: { $0.id == selectedId })
    {
      let displayBounds = imageToDisplay(annotation.bounds)
      if let handle = hitTestHandle(at: displayPoint, for: displayBounds) {
        isResizingAnnotation = true
        activeResizeHandle = handle
        originalBounds = annotation.bounds
        return
      }
    }

    // Crop tool
    if state.selectedTool == .crop {
      handleCropMouseDown(at: imagePoint)
      return
    }

    // Selection tool
    if state.selectedTool == .selection {
      if let annotation = state.selectAnnotation(at: imagePoint) {
        isDraggingAnnotation = true
        dragOffset = CGPoint(
          x: imagePoint.x - annotation.bounds.origin.x,
          y: imagePoint.y - annotation.bounds.origin.y
        )
        originalBounds = annotation.bounds
        NSCursor.closedHand.set()
        needsDisplay = true
        return
      } else {
        Task { @MainActor in
          state.deselectAnnotation()
        }
        needsDisplay = true
        return
      }
    }

    // Start drawing
    isDrawing = true
    switch state.selectedTool {
    case .pencil, .highlighter:
      currentPath = [imagePoint]
    case .text:
      Task { @MainActor in
        state.saveState()
        createTextAnnotation(at: imagePoint)
      }
      isDrawing = false
    default:
      break
    }
  }

  override func mouseDragged(with event: NSEvent) {
    let displayPoint = convert(event.locationInWindow, from: nil)
    let rawImagePoint = displayToImage(displayPoint)
    let imagePoint = clampToImageBounds(rawImagePoint)

    // Resizing annotation
    if isResizingAnnotation, let handle = activeResizeHandle,
       let selectedId = state.selectedAnnotationId
    {
      let newBounds = calculateResizedBounds(handle: handle, currentPoint: imagePoint)
      Task { @MainActor in
        state.updateAnnotationBounds(id: selectedId, bounds: newBounds)
      }
      needsDisplay = true
      return
    }

    // Crop resizing
    if isCropResizing, let handle = activeCropHandle {
      let shiftHeld = event.modifierFlags.contains(.shift)
      handleCropResize(handle: handle, currentPoint: imagePoint, shiftHeld: shiftHeld)
      Task { @MainActor in
        state.isCropResizing = true
        state.isCropShiftLocked = shiftHeld
      }
      needsDisplay = true
      return
    }

    // Crop dragging
    if isCropDragging {
      handleCropDrag(to: imagePoint)
      needsDisplay = true
      return
    }

    // Dragging annotation
    if isDraggingAnnotation, let selectedId = state.selectedAnnotationId {
      let newOrigin = CGPoint(
        x: imagePoint.x - dragOffset.x,
        y: imagePoint.y - dragOffset.y
      )
      let newBounds = CGRect(origin: newOrigin, size: originalBounds.size)
      Task { @MainActor in
        state.updateAnnotationBounds(id: selectedId, bounds: newBounds)
      }
      needsDisplay = true
      return
    }

    // Drawing
    guard isDrawing else { return }

    switch state.selectedTool {
    case .pencil, .highlighter:
      currentPath.append(imagePoint)
      needsDisplay = true
    default:
      currentPath = [imagePoint]
      needsDisplay = true
    }
  }

  override func mouseUp(with event: NSEvent) {
    let displayPoint = convert(event.locationInWindow, from: nil)
    let rawImagePoint = displayToImage(displayPoint)
    let imagePoint = clampToImageBounds(rawImagePoint)

    if isResizingAnnotation {
      if let selectedId = state.selectedAnnotationId,
         let annotation = state.annotations.first(where: { $0.id == selectedId }),
         case .blur = annotation.type
      {
        blurCacheManager.invalidate(id: selectedId)
      }
      Task { @MainActor in
        state.saveState()
      }
      isResizingAnnotation = false
      activeResizeHandle = nil
      needsDisplay = true
      return
    }

    if isCropResizing || isCropDragging {
      isCropResizing = false
      isCropDragging = false
      activeCropHandle = nil
      Task { @MainActor in
        state.isCropResizing = false
        state.isCropShiftLocked = false
      }
      needsDisplay = true
      return
    }

    if isDraggingAnnotation {
      Task { @MainActor in
        state.saveState()
      }
      isDraggingAnnotation = false
      updateCursor(for: event)
      needsDisplay = true
      return
    }

    guard isDrawing, let start = dragStart else { return }

    let pathToSave = currentPath

    Task { @MainActor in
      state.saveState()
      createAnnotation(from: start, to: imagePoint, path: pathToSave)
    }

    isDrawing = false
    dragStart = nil
    currentPath = []
    needsDisplay = true
  }

  private func calculateResizedBounds(handle: ResizeHandle, currentPoint: CGPoint) -> CGRect {
    var newBounds = originalBounds

    switch handle {
    case .topLeft:
      newBounds.origin.x = currentPoint.x
      newBounds.size.width = originalBounds.maxX - currentPoint.x
      newBounds.size.height = currentPoint.y - originalBounds.minY
    case .topRight:
      newBounds.size.width = currentPoint.x - originalBounds.minX
      newBounds.size.height = currentPoint.y - originalBounds.minY
    case .bottomLeft:
      newBounds.origin.x = currentPoint.x
      newBounds.origin.y = currentPoint.y
      newBounds.size.width = originalBounds.maxX - currentPoint.x
      newBounds.size.height = originalBounds.maxY - currentPoint.y
    case .bottomRight:
      newBounds.origin.y = currentPoint.y
      newBounds.size.width = currentPoint.x - originalBounds.minX
      newBounds.size.height = originalBounds.maxY - currentPoint.y
    default:
      break
    }

    if newBounds.width < 20 { newBounds.size.width = 20 }
    if newBounds.height < 20 { newBounds.size.height = 20 }

    return newBounds
  }

  // MARK: - Annotation Creation

  private func createAnnotation(from start: CGPoint, to end: CGPoint, path: [CGPoint]) {
    let item = AnnotationFactory.createAnnotation(
      tool: state.selectedTool,
      from: start,
      to: end,
      path: path,
      state: state
    )
    if let item {
      state.annotations.append(item)
    }
  }

  private func createTextAnnotation(at point: CGPoint) {
    let bounds = CGRect(x: point.x, y: point.y - 24, width: 100, height: 28)
    let properties = AnnotationProperties(
      strokeColor: state.strokeColor,
      fillColor: .clear,
      strokeWidth: state.strokeWidth,
      fontSize: 16,
      fontName: "SF Pro"
    )
    let item = AnnotationItem(type: .text(""), bounds: bounds, properties: properties)
    state.annotations.append(item)
    state.selectedAnnotationId = item.id
    state.editingTextAnnotationId = item.id
  }

  // MARK: - Drawing

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard let context = NSGraphicsContext.current?.cgContext else { return }

    context.saveGState()
    context.scaleBy(x: displayScale, y: displayScale)

    let renderer = AnnotationRenderer(
      context: context,
      editingTextId: state.editingTextAnnotationId,
      sourceImage: state.sourceImage,
      blurCacheManager: blurCacheManager
    )
    for annotation in state.annotations {
      renderer.draw(annotation)

      if annotation.id == state.selectedAnnotationId {
        drawSelectionHandles(for: annotation.bounds, in: context)
      }
    }

    // Draw current stroke preview
    if isDrawing, let start = dragStart {
      if state.selectedTool == .blur, let lastPoint = currentPath.last {
        renderer.drawBlurPreview(
          start: start,
          currentPoint: lastPoint,
          strokeColor: state.strokeColor,
          blurType: state.blurType
        )
      } else {
        renderer.drawCurrentStroke(
          tool: state.selectedTool,
          start: start,
          currentPath: currentPath,
          strokeColor: state.strokeColor,
          strokeWidth: state.strokeWidth
        )
      }
    }

    context.restoreGState()
  }

  private func drawSelectionHandles(for bounds: CGRect, in context: CGContext) {
    context.setStrokeColor(NSColor.systemBlue.cgColor)
    context.setLineWidth(1)
    context.setLineDash(phase: 0, lengths: [4, 4])
    context.stroke(bounds)
    context.setLineDash(phase: 0, lengths: [])

    let corners = [
      CGPoint(x: bounds.minX, y: bounds.minY),
      CGPoint(x: bounds.maxX, y: bounds.minY),
      CGPoint(x: bounds.minX, y: bounds.maxY),
      CGPoint(x: bounds.maxX, y: bounds.maxY),
    ]

    context.setFillColor(NSColor.white.cgColor)
    context.setStrokeColor(NSColor.systemBlue.cgColor)
    context.setLineWidth(1)

    for corner in corners {
      let rect = handleRect(at: corner)
      context.fill(rect)
      context.stroke(rect)
    }
  }

  // MARK: - Cursor Management

  override func mouseMoved(with event: NSEvent) {
    updateCursor(for: event)
  }

  private func updateCursor(for event: NSEvent) {
    let displayPoint = convert(event.locationInWindow, from: nil)
    let imagePoint = displayToImage(displayPoint)

    if let selectedId = state.selectedAnnotationId,
       let annotation = state.annotations.first(where: { $0.id == selectedId })
    {
      let displayBounds = imageToDisplay(annotation.bounds)
      if let handle = hitTestHandle(at: displayPoint, for: displayBounds) {
        setCursorForHandle(handle)
        return
      }

      if annotation.containsPoint(imagePoint) {
        NSCursor.openHand.set()
        return
      }
    }

    if state.selectedTool == .selection {
      if hitTestAnnotation(at: imagePoint) != nil {
        NSCursor.pointingHand.set()
        return
      }
    }

    if state.selectedTool == .crop, let cropRect = state.cropRect {
      if let handle = hitTestCropHandle(at: imagePoint, for: cropRect) {
        setCursorForCropHandle(handle)
        return
      }
      if cropRect.contains(imagePoint) {
        NSCursor.openHand.set()
        return
      }
    }

    NSCursor.arrow.set()
  }

  private func setCursorForHandle(_ handle: ResizeHandle) {
    switch handle {
    case .topLeft, .bottomRight:
      NSCursor.crosshair.set()
    case .topRight, .bottomLeft:
      NSCursor.crosshair.set()
    case .top, .bottom:
      NSCursor.resizeUpDown.set()
    case .left, .right:
      NSCursor.resizeLeftRight.set()
    }
  }

  private func setCursorForCropHandle(_ handle: CropHandle) {
    switch handle {
    case .topLeft, .bottomRight:
      NSCursor.crosshair.set()
    case .topRight, .bottomLeft:
      NSCursor.crosshair.set()
    case .top, .bottom:
      NSCursor.resizeUpDown.set()
    case .left, .right:
      NSCursor.resizeLeftRight.set()
    case .body:
      NSCursor.openHand.set()
    }
  }

  // MARK: - Crop Handling

  private func handleCropMouseDown(at imagePoint: CGPoint) {
    if state.cropRect == nil {
      Task { @MainActor in
        state.initializeCrop()
      }
      return
    }

    if !state.isCropActive {
      Task { @MainActor in
        state.isCropActive = true
      }
    }

    guard let cropRect = state.cropRect else { return }

    if let handle = hitTestCropHandle(at: imagePoint, for: cropRect) {
      if handle == .body {
        isCropDragging = true
        dragOffset = CGPoint(
          x: imagePoint.x - cropRect.origin.x,
          y: imagePoint.y - cropRect.origin.y
        )
      } else {
        isCropResizing = true
        activeCropHandle = handle
      }
      originalCropRect = cropRect
    } else if cropRect.contains(imagePoint) {
      isCropDragging = true
      dragOffset = CGPoint(
        x: imagePoint.x - cropRect.origin.x,
        y: imagePoint.y - cropRect.origin.y
      )
      originalCropRect = cropRect
    }
  }

  private func hitTestCropHandle(at point: CGPoint, for cropRect: CGRect) -> CropHandle? {
    let handleRadius: CGFloat = max(15, 12 / displayScale)

    let handles: [(CropHandle, CGPoint)] = [
      (.topLeft, CGPoint(x: cropRect.minX, y: cropRect.maxY)),
      (.top, CGPoint(x: cropRect.midX, y: cropRect.maxY)),
      (.topRight, CGPoint(x: cropRect.maxX, y: cropRect.maxY)),
      (.left, CGPoint(x: cropRect.minX, y: cropRect.midY)),
      (.right, CGPoint(x: cropRect.maxX, y: cropRect.midY)),
      (.bottomLeft, CGPoint(x: cropRect.minX, y: cropRect.minY)),
      (.bottom, CGPoint(x: cropRect.midX, y: cropRect.minY)),
      (.bottomRight, CGPoint(x: cropRect.maxX, y: cropRect.minY)),
    ]

    for (handle, center) in handles {
      let distance = hypot(point.x - center.x, point.y - center.y)
      if distance <= handleRadius {
        return handle
      }
    }

    return nil
  }

  private func handleCropResize(handle: CropHandle, currentPoint: CGPoint, shiftHeld: Bool = false) {
    var newRect = originalCropRect

    let imageWidth = state.imageWidth
    let imageHeight = state.imageHeight
    let clampedPoint = CGPoint(
      x: max(0, min(currentPoint.x, imageWidth)),
      y: max(0, min(currentPoint.y, imageHeight))
    )

    let minSize: CGFloat = 20

    switch handle {
    case .topLeft:
      let maxX = originalCropRect.maxX - minSize
      let minY = originalCropRect.minY + minSize
      newRect.origin.x = min(clampedPoint.x, maxX)
      newRect.size.width = originalCropRect.maxX - newRect.origin.x
      newRect.size.height = max(clampedPoint.y, minY) - originalCropRect.minY
    case .top:
      let minY = originalCropRect.minY + minSize
      newRect.size.height = max(clampedPoint.y, minY) - originalCropRect.minY
    case .topRight:
      let minX = originalCropRect.minX + minSize
      let minY = originalCropRect.minY + minSize
      newRect.size.width = max(clampedPoint.x, minX) - originalCropRect.minX
      newRect.size.height = max(clampedPoint.y, minY) - originalCropRect.minY
    case .left:
      let maxX = originalCropRect.maxX - minSize
      newRect.origin.x = min(clampedPoint.x, maxX)
      newRect.size.width = originalCropRect.maxX - newRect.origin.x
    case .right:
      let minX = originalCropRect.minX + minSize
      newRect.size.width = max(clampedPoint.x, minX) - originalCropRect.minX
    case .bottomLeft:
      let maxX = originalCropRect.maxX - minSize
      let maxY = originalCropRect.maxY - minSize
      newRect.origin.x = min(clampedPoint.x, maxX)
      newRect.origin.y = min(clampedPoint.y, maxY)
      newRect.size.width = originalCropRect.maxX - newRect.origin.x
      newRect.size.height = originalCropRect.maxY - newRect.origin.y
    case .bottom:
      let maxY = originalCropRect.maxY - minSize
      newRect.origin.y = min(clampedPoint.y, maxY)
      newRect.size.height = originalCropRect.maxY - newRect.origin.y
    case .bottomRight:
      let minX = originalCropRect.minX + minSize
      let maxY = originalCropRect.maxY - minSize
      newRect.origin.y = min(clampedPoint.y, maxY)
      newRect.size.width = max(clampedPoint.x, minX) - originalCropRect.minX
      newRect.size.height = originalCropRect.maxY - newRect.origin.y
    case .body:
      break
    }

    Task { @MainActor in
      state.updateCropRect(newRect)
    }
  }

  private func handleCropDrag(to point: CGPoint) {
    let newOrigin = CGPoint(
      x: point.x - dragOffset.x,
      y: point.y - dragOffset.y
    )
    var newRect = originalCropRect
    newRect.origin = newOrigin

    Task { @MainActor in
      state.updateCropRect(newRect)
    }
  }
}
