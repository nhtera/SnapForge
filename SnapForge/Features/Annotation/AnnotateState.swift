import AppKit
import Combine
import SwiftUI

/// Central state management for annotation window
/// Follows Snapzy's AnnotateState pattern with centralized ObservableObject
@MainActor
final class AnnotateState: ObservableObject {

  // MARK: - Source Image

  @Published var sourceImage: NSImage?
  @Published var sourceURL: URL?

  /// Whether an image is loaded
  var hasImage: Bool { sourceImage != nil }

  /// Image dimensions (convenience)
  var imageWidth: CGFloat { sourceImage?.size.width ?? 0 }
  var imageHeight: CGFloat { sourceImage?.size.height ?? 0 }

  // MARK: - Tool State

  @Published var selectedTool: AnnotationToolType = .selection
  @Published var strokeWidth: CGFloat = 3
  @Published var strokeColor: Color = .red
  @Published var fillColor: Color = .clear
  @Published var blurType: BlurType = .pixelated

  // MARK: - Annotation Storage

  @Published var annotations: [AnnotationItem] = []

  // MARK: - Selection State

  @Published var selectedAnnotationId: UUID?
  @Published var editingTextAnnotationId: UUID?

  // MARK: - Crop State

  @Published var cropRect: CGRect?
  @Published var isCropActive = false
  @Published var cropAspectRatio: CropAspectRatio = .free
  @Published var isCropResizing = false
  @Published var isCropShiftLocked = false
  var originalCropRect: CGRect?

  // MARK: - Undo/Redo

  @Published var canUndo = false
  @Published var canRedo = false
  @Published var hasUnsavedChanges = false
  private var undoStack: [[AnnotationItem]] = []
  private var redoStack: [[AnnotationItem]] = []

  // MARK: - Init

  init() {}

  // MARK: - Image Loading

  func loadImage(from url: URL) {
    sourceURL = url
    sourceImage = Self.loadImageWithCorrectScale(from: url)
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

  func loadImage(_ image: NSImage, url: URL? = nil) {
    sourceURL = url
    sourceImage = image
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
  }

  func redo() {
    guard let next = redoStack.popLast() else { return }
    undoStack.append(annotations)
    annotations = next
    canUndo = true
    canRedo = !redoStack.isEmpty
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
    default:
      break
    }
  }

  func updateAnnotationText(id: UUID, text: String) {
    if let index = annotations.firstIndex(where: { $0.id == id }) {
      annotations[index].type = .text(text)
      let newBounds = calculateTextBounds(
        text: text,
        fontSize: annotations[index].properties.fontSize,
        origin: annotations[index].bounds.origin
      )
      annotations[index].bounds = newBounds
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
  }

  /// Calculate text bounds based on content and font size
  private func calculateTextBounds(text: String, fontSize: CGFloat, origin: CGPoint) -> CGRect {
    let clampedFontSize = min(max(fontSize, 8), 144)
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: clampedFontSize)
    ]
    let displayText = text.isEmpty ? "Text" : text
    let size = (displayText as NSString).size(withAttributes: attributes)
    let padding: CGFloat = 4

    let maxWidth: CGFloat = 2000
    let maxHeight: CGFloat = 500

    return CGRect(
      x: origin.x,
      y: origin.y,
      width: min(size.width + padding * 2, maxWidth),
      height: min(size.height + padding * 2, maxHeight)
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
    default:
      break
    }
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
  }
}

// MARK: - Crop Aspect Ratio

enum CropAspectRatio: String, CaseIterable, Identifiable {
  case free
  case ratio1x1
  case ratio4x3
  case ratio16x9
  case ratio3x2
  case ratio9x16

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .free: return "Free"
    case .ratio1x1: return "1:1"
    case .ratio4x3: return "4:3"
    case .ratio16x9: return "16:9"
    case .ratio3x2: return "3:2"
    case .ratio9x16: return "9:16"
    }
  }

  /// Target ratio (width / height)
  var ratio: CGFloat {
    switch self {
    case .free: return 0
    case .ratio1x1: return 1
    case .ratio4x3: return 4.0 / 3.0
    case .ratio16x9: return 16.0 / 9.0
    case .ratio3x2: return 3.0 / 2.0
    case .ratio9x16: return 9.0 / 16.0
    }
  }
}
