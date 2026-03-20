import AppKit
import SwiftUI

/// Central state management for annotation window
@MainActor
@Observable
final class AnnotateState {

  // MARK: - Source Image

  var sourceImage: NSImage?
  var sourceURL: URL?

  /// Whether an image is loaded
  var hasImage: Bool { sourceImage != nil }

  /// Image dimensions (convenience)
  var imageWidth: CGFloat { sourceImage?.size.width ?? 0 }
  var imageHeight: CGFloat { sourceImage?.size.height ?? 0 }

  // MARK: - Tool State

  var selectedTool: AnnotationToolType = .selection
  var strokeWidth: CGFloat = 3
  var strokeColor: Color = .red
  var fillColor: Color = .clear
  var blurType: BlurType = .pixelated
  var fontSize: CGFloat = 16

  // MARK: - Annotation Storage

  var annotations: [AnnotationItem] = []

  // MARK: - Selection State

  var selectedAnnotationId: UUID?
  var editingTextAnnotationId: UUID?

  // MARK: - Crop State

  var cropRect: CGRect?
  var isCropActive = false
  var cropAspectRatio: CropAspectRatio = .free
  var isCropResizing = false
  var isCropShiftLocked = false
  var originalCropRect: CGRect?
  /// Set to true by Enter key handler to trigger real crop in AnnotationView
  var shouldApplyCrop = false

  // MARK: - Layers Panel State

  var isLayersPanelVisible = false
  var hiddenAnnotationIds: Set<UUID> = []
  var lockedAnnotationIds: Set<UUID> = []

  // MARK: - Redact State

  var redactRegions: [RedactRegion] = []
  var isRedactScanning = false

  // MARK: - Sticker State

  var isStickerLibraryVisible = false

  // MARK: - Zoom State

  var zoomLevel: CGFloat = 1.0
  let zoomRange: ClosedRange<CGFloat> = 0.25...4.0
  private let zoomStep: CGFloat = 0.1

  func zoomIn() {
    zoomLevel = min(zoomLevel + zoomStep, zoomRange.upperBound)
    bumpRevision()
  }

  func zoomOut() {
    zoomLevel = max(zoomLevel - zoomStep, zoomRange.lowerBound)
    bumpRevision()
  }

  func resetZoom() {
    zoomLevel = 1.0
    bumpRevision()
  }

  // MARK: - Revision Counter (triggers NSView redraws)

  /// Incremented on every state mutation to force NSViewRepresentable `updateNSView` calls.
  /// Without this, SwiftUI may skip `updateNSView` because the struct reference hasn't changed.
  var revision: UInt = 0

  /// Bump the revision counter to signal a visual change
  func bumpRevision() { revision &+= 1 }

  // MARK: - Undo/Redo

  var canUndo = false
  var canRedo = false
  var hasUnsavedChanges = false
  private var undoStack: [[AnnotationItem]] = []
  private var redoStack: [[AnnotationItem]] = []

  // MARK: - Init

  init() {}

  // MARK: - Image Loading

  func loadImage(from url: URL) {
    sourceURL = url
    sourceImage = Self.loadImageWithCorrectScale(from: url)
    resetState()
  }

  func loadImage(_ image: NSImage, url: URL? = nil) {
    sourceURL = url
    sourceImage = image
    resetState()
  }

  private func resetState() {
    annotations.removeAll()
    undoStack.removeAll()
    redoStack.removeAll()
    canUndo = false
    canRedo = false
    selectedAnnotationId = nil
    editingTextAnnotationId = nil
    cropRect = nil
    isCropActive = false
    hasUnsavedChanges = false
  }

  /// Load image and adjust size for Retina displays
  private static func loadImageWithCorrectScale(from url: URL) -> NSImage? {
    guard let image = NSImage(contentsOf: url) else { return nil }

    guard let bitmapRep = image.representations.first as? NSBitmapImageRep else {
      if let rep = image.representations.first {
        let pixelWidth = rep.pixelsWide
        let pixelHeight = rep.pixelsHigh
        if pixelWidth > 0 && pixelHeight > 0 {
          let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
          image.size = NSSize(
            width: CGFloat(pixelWidth) / scaleFactor,
            height: CGFloat(pixelHeight) / scaleFactor
          )
        }
      }
      return image
    }

    let pixelWidth = bitmapRep.pixelsWide
    let pixelHeight = bitmapRep.pixelsHigh
    let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
    image.size = NSSize(
      width: CGFloat(pixelWidth) / scaleFactor,
      height: CGFloat(pixelHeight) / scaleFactor
    )

    return image
  }

  // MARK: - Undo/Redo

  func saveState() {
    undoStack.append(annotations)
    redoStack.removeAll()
    canUndo = true
    canRedo = false
    hasUnsavedChanges = true
  }

  func undo() {
    guard let previous = undoStack.popLast() else { return }
    redoStack.append(annotations)
    annotations = previous
    canUndo = !undoStack.isEmpty
    canRedo = true
    bumpRevision()
  }

  func redo() {
    guard let next = redoStack.popLast() else { return }
    undoStack.append(annotations)
    annotations = next
    canUndo = true
    canRedo = !redoStack.isEmpty
    bumpRevision()
  }

  /// Clear undo/redo history (e.g. after crop changes coordinates)
  func clearUndoHistory() {
    undoStack.removeAll()
    redoStack.removeAll()
    canUndo = false
    canRedo = false
  }

  // MARK: - Counter

  /// Derive next counter value from existing annotations (undo-safe)
  func nextCounterValue() -> Int {
    let maxExisting = annotations.compactMap { annotation -> Int? in
      if case .counter(let v) = annotation.type { return v }
      return nil
    }.max() ?? 0
    return maxExisting + 1
  }

  // MARK: - Crop

  /// Initialize crop to slightly inset from full image (handles visible inside)
  func initializeCrop() {
    let insetFraction: CGFloat = 0.05
    let insetX = imageWidth * insetFraction
    let insetY = imageHeight * insetFraction
    let initialRect = CGRect(
      x: insetX,
      y: insetY,
      width: imageWidth - insetX * 2,
      height: imageHeight - insetY * 2
    )
    cropRect = initialRect
    originalCropRect = initialRect
    isCropActive = true
  }

  /// Apply crop (confirm)
  func applyCrop() {
    isCropActive = false
    hasUnsavedChanges = true
  }

  /// Cancel crop and reset
  func cancelCrop() {
    cropRect = nil
    isCropActive = false
    selectedTool = .selection
  }

  /// Reset crop to nil
  func resetCrop() {
    cropRect = nil
    isCropActive = false
    cropAspectRatio = .free
    isCropResizing = false
    isCropShiftLocked = false
  }

  /// Apply aspect ratio to current crop rect
  func applyCropAspectRatio(_ ratio: CropAspectRatio) {
    cropAspectRatio = ratio

    guard var rect = originalCropRect ?? cropRect, ratio != .free else { return }

    let targetRatio = ratio.ratio
    let currentRatio = rect.width / rect.height

    if currentRatio > targetRatio {
      let newWidth = rect.height * targetRatio
      rect.origin.x += (rect.width - newWidth) / 2
      rect.size.width = newWidth
    } else {
      let newHeight = rect.width / targetRatio
      rect.origin.y += (rect.height - newHeight) / 2
      rect.size.height = newHeight
    }

    cropRect = constrainCropToImageBounds(rect)
  }

  /// Update crop rect with bounds constraint
  func updateCropRect(_ newRect: CGRect) {
    cropRect = constrainCropToImageBounds(newRect)
  }

  /// Constrain crop rect to image bounds with minimum size
  private func constrainCropToImageBounds(_ rect: CGRect) -> CGRect {
    var constrained = rect

    let minSize: CGFloat = 20
    if constrained.width < minSize { constrained.size.width = minSize }
    if constrained.height < minSize { constrained.size.height = minSize }

    constrained.origin.x = max(0, constrained.origin.x)
    constrained.origin.y = max(0, constrained.origin.y)

    if constrained.maxX > imageWidth {
      constrained.origin.x = imageWidth - constrained.width
    }
    if constrained.maxY > imageHeight {
      constrained.origin.y = imageHeight - constrained.height
    }

    constrained.origin.x = max(0, constrained.origin.x)
    constrained.origin.y = max(0, constrained.origin.y)

    return constrained
  }

  // MARK: - Annotation Selection

  @discardableResult
  func selectAnnotation(at point: CGPoint) -> AnnotationItem? {
    for annotation in annotations.reversed() {
      // Skip hidden or locked annotations
      guard !hiddenAnnotationIds.contains(annotation.id),
            !lockedAnnotationIds.contains(annotation.id) else { continue }

      let expandedBounds = annotation.bounds.insetBy(dx: -10, dy: -10)
      guard expandedBounds.contains(point) else { continue }

      if annotation.containsPoint(point) {
        selectedAnnotationId = annotation.id
        return annotation
      }
    }
    selectedAnnotationId = nil
    return nil
  }

  func updateAnnotationBounds(id: UUID, bounds: CGRect) {
    guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }

    let oldBounds = annotations[index].bounds
    let dx = bounds.origin.x - oldBounds.origin.x
    let dy = bounds.origin.y - oldBounds.origin.y

    annotations[index].bounds = bounds

    // Also update embedded coordinates for arrows/lines/paths
    switch annotations[index].type {
    case .arrow(let start, let end):
      annotations[index].type = .arrow(
        start: CGPoint(x: start.x + dx, y: start.y + dy),
        end: CGPoint(x: end.x + dx, y: end.y + dy)
      )
    case .line(let start, let end):
      annotations[index].type = .line(
        start: CGPoint(x: start.x + dx, y: start.y + dy),
        end: CGPoint(x: end.x + dx, y: end.y + dy)
      )
    case .path(let points):
      annotations[index].type = .path(points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) })
    case .highlight(let points):
      annotations[index].type = .highlight(points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) })
    case .ruler(let start, let end):
      annotations[index].type = .ruler(
        start: CGPoint(x: start.x + dx, y: start.y + dy),
        end: CGPoint(x: end.x + dx, y: end.y + dy)
      )
    default:
      break
    }
    bumpRevision()
  }

  func updateAnnotationText(id: UUID, text: String) {
    if let index = annotations.firstIndex(where: { $0.id == id }) {
      annotations[index].type = .text(text)
      // Keep top edge (maxY) fixed so first line stays in place.
      // Height grows downward in CG coords (origin.y decreases).
      let oldMaxY = annotations[index].bounds.maxY
      let newBounds = calculateTextBounds(
        text: text,
        fontSize: annotations[index].properties.fontSize,
        origin: annotations[index].bounds.origin
      )
      annotations[index].bounds = CGRect(
        x: newBounds.origin.x,
        y: oldMaxY - newBounds.height,
        width: newBounds.width,
        height: newBounds.height
      )
      bumpRevision()
    }
  }

  /// Update annotation properties
  func updateAnnotationProperties(
    id: UUID,
    strokeWidth: CGFloat? = nil,
    fontSize: CGFloat? = nil,
    strokeColor: Color? = nil,
    fillColor: Color? = nil
  ) {
    guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }

    if let strokeWidth {
      annotations[index].properties.strokeWidth = strokeWidth
    }
    if let fontSize {
      annotations[index].properties.fontSize = fontSize
      if case .text(let content) = annotations[index].type {
        annotations[index].bounds = calculateTextBounds(
          text: content,
          fontSize: fontSize,
          origin: annotations[index].bounds.origin
        )
      }
    }
    if let strokeColor {
      annotations[index].properties.strokeColor = strokeColor
    }
    if let fillColor {
      annotations[index].properties.fillColor = fillColor
    }
    bumpRevision()
  }

  /// Calculate text bounds based on content and font size.
  /// Uses shared TextAnnotationLayout for consistent multiline metrics with renderer.
  private func calculateTextBounds(text: String, fontSize: CGFloat, origin: CGPoint) -> CGRect {
    let clampedFontSize = min(max(fontSize, 8), 144)
    let padding = TextAnnotationLayout.horizontalPadding
    let verticalPadding = TextAnnotationLayout.verticalPadding
    let minHeight = TextAnnotationLayout.minimumHeight(for: clampedFontSize)
    let minWidth = TextAnnotationLayout.minWidth

    let displayText = text.isEmpty ? "Text" : text
    let maxTextWidth: CGFloat = 2000

    let textSize = TextAnnotationLayout.multilineBounds(
      text: displayText,
      fontSize: clampedFontSize,
      maxWidth: maxTextWidth
    )

    let width = max(textSize.width + padding * 2, minWidth)
    let height = max(textSize.height + verticalPadding * 2, minHeight)

    return CGRect(
      x: origin.x,
      y: origin.y,
      width: min(width, maxTextWidth + padding * 2),
      height: min(height, 2000)
    )
  }

  /// Get selected annotation
  var selectedAnnotation: AnnotationItem? {
    guard let id = selectedAnnotationId else { return nil }
    return annotations.first { $0.id == id }
  }

  /// Get selected text annotation
  var selectedTextAnnotation: AnnotationItem? {
    guard let id = selectedAnnotationId,
          let annotation = annotations.first(where: { $0.id == id }),
          case .text = annotation.type else {
      return nil
    }
    return annotation
  }

  func deleteSelectedAnnotation() {
    guard let selectedId = selectedAnnotationId else { return }
    saveState()
    annotations.removeAll { $0.id == selectedId }
    selectedAnnotationId = nil
    bumpRevision()
  }

  /// Remove a specific annotation by ID
  func removeAnnotation(id: UUID) {
    saveState()
    annotations.removeAll { $0.id == id }
    if selectedAnnotationId == id { selectedAnnotationId = nil }
    bumpRevision()
  }

  func deselectAnnotation() {
    selectedAnnotationId = nil
    editingTextAnnotationId = nil
  }

  /// Nudge selected annotation by delta
  func nudgeSelectedAnnotation(dx: CGFloat, dy: CGFloat) {
    guard let selectedId = selectedAnnotationId,
          let index = annotations.firstIndex(where: { $0.id == selectedId }) else { return }

    saveState()
    annotations[index].bounds.origin.x += dx
    annotations[index].bounds.origin.y += dy

    switch annotations[index].type {
    case .arrow(let start, let end):
      annotations[index].type = .arrow(
        start: CGPoint(x: start.x + dx, y: start.y + dy),
        end: CGPoint(x: end.x + dx, y: end.y + dy)
      )
    case .line(let start, let end):
      annotations[index].type = .line(
        start: CGPoint(x: start.x + dx, y: start.y + dy),
        end: CGPoint(x: end.x + dx, y: end.y + dy)
      )
    case .path(let points):
      annotations[index].type = .path(points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) })
    case .highlight(let points):
      annotations[index].type = .highlight(points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) })
    case .ruler(let start, let end):
      annotations[index].type = .ruler(
        start: CGPoint(x: start.x + dx, y: start.y + dy),
        end: CGPoint(x: end.x + dx, y: end.y + dy)
      )
    default:
      break
    }
    bumpRevision()
  }

  /// Mark as saved (reset unsaved changes flag)
  func markAsSaved() {
    hasUnsavedChanges = false
  }

  /// Clear all annotations
  func clearAll() {
    guard !annotations.isEmpty else { return }
    saveState()
    annotations.removeAll()
    selectedAnnotationId = nil
    editingTextAnnotationId = nil
    hiddenAnnotationIds.removeAll()
    lockedAnnotationIds.removeAll()
    bumpRevision()
  }

  // MARK: - Layer Management

  /// Toggle visibility of an annotation
  func toggleVisibility(id: UUID) {
    if hiddenAnnotationIds.contains(id) {
      hiddenAnnotationIds.remove(id)
    } else {
      hiddenAnnotationIds.insert(id)
      // Deselect if hiding the selected annotation
      if selectedAnnotationId == id {
        selectedAnnotationId = nil
      }
    }
    bumpRevision()
  }

  /// Toggle lock state of an annotation
  func toggleLock(id: UUID) {
    if lockedAnnotationIds.contains(id) {
      lockedAnnotationIds.remove(id)
    } else {
      lockedAnnotationIds.insert(id)
      // Deselect if locking the selected annotation
      if selectedAnnotationId == id {
        selectedAnnotationId = nil
      }
    }
    bumpRevision()
  }

  /// Move annotation from one index to another (for reordering layers)
  func moveAnnotation(from source: IndexSet, to destination: Int) {
    saveState()
    annotations.move(fromOffsets: source, toOffset: destination)
    bumpRevision()
  }

  /// Check if an annotation is visible
  func isAnnotationVisible(_ id: UUID) -> Bool {
    !hiddenAnnotationIds.contains(id)
  }

  /// Check if an annotation is locked
  func isAnnotationLocked(_ id: UUID) -> Bool {
    lockedAnnotationIds.contains(id)
  }

  // MARK: - Redact

  /// Start auto-redact scanning
  func startRedact() {
    guard let image = sourceImage else { return }
    isRedactScanning = true
    redactRegions = []

    Task {
      let regions = await AutoRedactService.shared.detectSensitiveRegions(in: image)
      self.redactRegions = regions
      self.isRedactScanning = false
    }
  }

  /// Cancel redaction and clear regions
  func cancelRedact() {
    redactRegions = []
    isRedactScanning = false
    selectedTool = .selection
  }

  /// Apply selected redact regions as blur annotations
  func applyRedactions() {
    saveState()
    for region in redactRegions where region.isSelected {
      // Flip Y: detection coordinates use top-left origin (SwiftUI),
      // but canvas renders in bottom-left origin (NSView/CoreGraphics)
      // Expand bounds slightly for better coverage of text edges
      let padding: CGFloat = 8
      let paddedBounds = CGRect(
        x: region.bounds.origin.x - padding,
        y: imageHeight - region.bounds.origin.y - region.bounds.height - padding,
        width: region.bounds.width + padding * 2,
        height: region.bounds.height + padding * 2
      )
      // Dynamic pixel size: softer mosaic with ~8-10 blocks across
      let dynamicPixelSize = max(
        paddedBounds.width / 8,
        paddedBounds.height * 0.6,
        15
      )
      let annotation = AnnotationItem(
        type: .blur(.pixelated),
        bounds: paddedBounds,
        properties: AnnotationProperties(
          strokeColor: .clear,
          strokeWidth: 0,
          pixelSize: dynamicPixelSize
        )
      )
      annotations.append(annotation)
    }
    redactRegions = []
    selectedTool = .selection
    bumpRevision()
  }

  // MARK: - Sticker Placement

  /// Place a sticker at the center of the canvas
  func placeSticker(_ sticker: StickerItem) {
    saveState()
    let stickerSize: CGFloat = 60
    let centerX = imageWidth / 2 - stickerSize / 2
    let centerY = imageHeight / 2 - stickerSize / 2
    let bounds = CGRect(x: centerX, y: centerY, width: stickerSize, height: stickerSize)

    let annotation = AnnotationItem(
      type: .sticker(sticker),
      bounds: bounds,
      properties: AnnotationProperties(strokeColor: self.strokeColor)
    )
    annotations.append(annotation)
    selectedAnnotationId = annotation.id
    bumpRevision()
  }
}
