import AppKit
import SwiftUI

/// NSViewRepresentable wrapper for the drawing canvas
struct CanvasDrawingView: NSViewRepresentable {
  var state: AnnotateState
  var displayScale: CGFloat = 1.0
  /// Changing revision value forces SwiftUI to call updateNSView
  var revision: UInt = 0

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
@MainActor
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

  // MARK: - Scroll-to-Zoom

  override func scrollWheel(with event: NSEvent) {
    // Use vertical scroll delta to zoom in/out
    let delta = event.scrollingDeltaY
    guard abs(delta) > 0.1 else { return }

    let zoomFactor: CGFloat = 0.02
    let newZoom = state.zoomLevel + delta * zoomFactor
    state.zoomLevel = min(max(newZoom, state.zoomRange.lowerBound), state.zoomRange.upperBound)
    state.bumpRevision()
  }

  override func magnify(with event: NSEvent) {
    let newZoom = state.zoomLevel * (1.0 + event.magnification)
    state.zoomLevel = min(max(newZoom, state.zoomRange.lowerBound), state.zoomRange.upperBound)
    state.bumpRevision()
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
        state.deleteSelectedAnnotation()
        needsDisplay = true
      }

    case 53: // Escape
      if state.selectedTool == .crop && state.isCropActive {
        state.cancelCrop()
        needsDisplay = true
        return
      }
      state.deselectAnnotation()
      needsDisplay = true

    case 36: // Enter — confirm crop
      if state.selectedTool == .crop && state.isCropActive {
        state.applyCrop()
        state.selectedTool = .selection
        needsDisplay = true
        return
      }

    case 126: // Arrow Up
      if state.selectedAnnotationId != nil && state.editingTextAnnotationId == nil {
        state.nudgeSelectedAnnotation(dx: 0, dy: nudgeAmount)
        needsDisplay = true
      }

    case 125: // Arrow Down
      if state.selectedAnnotationId != nil && state.editingTextAnnotationId == nil {
        state.nudgeSelectedAnnotation(dx: 0, dy: -nudgeAmount)
        needsDisplay = true
      }

    case 123: // Arrow Left
      if state.selectedAnnotationId != nil && state.editingTextAnnotationId == nil {
        state.nudgeSelectedAnnotation(dx: -nudgeAmount, dy: 0)
        needsDisplay = true
      }

    case 124: // Arrow Right
      if state.selectedAnnotationId != nil && state.editingTextAnnotationId == nil {
        state.nudgeSelectedAnnotation(dx: nudgeAmount, dy: 0)
        needsDisplay = true
      }

    case 6: // Z key — Undo/Redo
      if event.modifierFlags.contains(.command) {
        if event.modifierFlags.contains(.shift) {
          state.redo()
        } else {
          state.undo()
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
          state.selectedTool = tool
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
      // Skip hidden annotations
      guard !state.hiddenAnnotationIds.contains(annotation.id) else { continue }
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
    // Ensure canvas is first responder (may have lost focus to tool palette buttons)
    window?.makeFirstResponder(self)

    let displayPoint = convert(event.locationInWindow, from: nil)
    let rawImagePoint = displayToImage(displayPoint)
    let imagePoint = clampToImageBounds(rawImagePoint)
    dragStart = imagePoint

    // Double-click on text to edit
    if event.clickCount == 2 {
      if let annotation = hitTestAnnotation(at: imagePoint),
         case .text = annotation.type
      {
        state.editingTextAnnotationId = annotation.id
        state.selectedAnnotationId = annotation.id
        needsDisplay = true
        return
      }
    }

    // Commit and finalize current text editing.
    // TextEditOverlay live-syncs editingText → annotation on every keystroke,
    // so the annotation already has the latest text. We just need to:
    // 1. Clear the editing state
    // 2. Delete empty text annotations
    // 3. Let the click flow through (sticky tool — creates new text if .text tool)
    if let editingId = state.editingTextAnnotationId {
      state.editingTextAnnotationId = nil
      // Clean up empty text annotation
      if let annotation = state.annotations.first(where: { $0.id == editingId }),
         case .text(let text) = annotation.type,
         text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        state.annotations.removeAll { $0.id == editingId }
        if state.selectedAnnotationId == editingId {
          state.selectedAnnotationId = nil
        }
      }
      needsDisplay = true
    }

    // Check resize handles on selected annotation (only in selection mode)
    if state.selectedTool == .selection,
       let selectedId = state.selectedAnnotationId,
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
        state.deselectAnnotation()
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
      // Smart text tool:
      // - Click on existing annotation → select and start dragging
      // - Click on blank space → create new text annotation
      if let annotation = hitTestAnnotation(at: imagePoint) {
        // Hit an existing annotation — select and drag it
        state.selectedAnnotationId = annotation.id
        isDraggingAnnotation = true
        dragOffset = CGPoint(
          x: imagePoint.x - annotation.bounds.origin.x,
          y: imagePoint.y - annotation.bounds.origin.y
        )
        originalBounds = annotation.bounds
        NSCursor.closedHand.set()
        isDrawing = false
      } else {
        // Blank space — create new text annotation
        state.saveState()
        createTextAnnotation(at: imagePoint)
        isDrawing = false
      }
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
      state.updateAnnotationBounds(id: selectedId, bounds: newBounds)
      needsDisplay = true
      return
    }

    // Crop resizing
    if isCropResizing, let handle = activeCropHandle {
      let shiftHeld = event.modifierFlags.contains(.shift)
      handleCropResize(handle: handle, currentPoint: imagePoint, shiftHeld: shiftHeld)
      state.isCropResizing = true
      state.isCropShiftLocked = shiftHeld
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
      state.updateAnnotationBounds(id: selectedId, bounds: newBounds)
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
      state.saveState()
      isResizingAnnotation = false
      activeResizeHandle = nil
      needsDisplay = true
      return
    }

    if isCropResizing || isCropDragging {
      isCropResizing = false
      isCropDragging = false
      activeCropHandle = nil
      state.isCropResizing = false
      state.isCropShiftLocked = false
      needsDisplay = true
      return
    }

    if isDraggingAnnotation {
      state.saveState()
      isDraggingAnnotation = false
      updateCursor(for: event)
      needsDisplay = true
      return
    }

    guard isDrawing, let start = dragStart else { return }

    let pathToSave = currentPath

    state.saveState()
    createAnnotation(from: start, to: imagePoint, path: pathToSave)

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
    // Scale-aware font size: ensure text appears at ~16pt on screen
    // regardless of the image-to-canvas scale factor
    let desiredScreenSize: CGFloat = 16
    let fontSize = max(desiredScreenSize / displayScale, desiredScreenSize)

    // Calculate proper height from font metrics
    let font = NSFont.systemFont(ofSize: fontSize)
    let textHeight = font.ascender - font.descender + font.leading
    let padding: CGFloat = 4
    let totalHeight = textHeight + padding * 2
    let initialWidth = max(150 / displayScale, 150)

    // Position bounds so text appears at the click point
    let bounds = CGRect(x: point.x, y: point.y - padding, width: initialWidth, height: totalHeight)
    let properties = AnnotationProperties(
      strokeColor: state.strokeColor,
      fillColor: .clear,
      strokeWidth: state.strokeWidth,
      fontSize: fontSize,
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
      // Skip hidden annotations
      guard !state.hiddenAnnotationIds.contains(annotation.id) else { continue }

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

    if state.selectedTool == .selection || state.selectedTool == .text {
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
      state.initializeCrop()
      return
    }

    if !state.isCropActive {
      state.isCropActive = true
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

    state.updateCropRect(newRect)
  }

  private func handleCropDrag(to point: CGPoint) {
    let newOrigin = CGPoint(
      x: point.x - dragOffset.x,
      y: point.y - dragOffset.y
    )
    var newRect = originalCropRect
    newRect.origin = newOrigin

    state.updateCropRect(newRect)
  }
}
