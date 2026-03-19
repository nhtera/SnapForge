import AppKit
import SwiftUI

/// Overlay for editing text annotations inline on the canvas.
/// Uses AppKit NSTextField (not SwiftUI TextField) to ensure pixel-perfect
/// alignment with the Core Graphics renderer — both use the same NSFont.
struct TextEditOverlay: View {
  var state: AnnotateState
  let scale: CGFloat
  let imageSize: CGSize

  @State private var editingText: String = ""

  private let minTextFieldWidth: CGFloat = 60

  var body: some View {
    ZStack {
      if let editingId = state.editingTextAnnotationId,
         let annotation = state.annotations.first(where: { $0.id == editingId }),
         case .text(let currentText) = annotation.type
      {
        let displayBounds = calculateDisplayBounds(annotation.bounds)
        let fontSize = max(annotation.properties.fontSize * scale, 10)
        let frameWidth = max(displayBounds.width, minTextFieldWidth)

        NativeAnnotationTextField(
          text: $editingText,
          font: TextAnnotationLayout.font(size: fontSize),
          textColor: NSColor(annotation.properties.strokeColor),
          horizontalInset: TextAnnotationLayout.horizontalPadding * scale,
          onCommit: { commitEdit(id: editingId) },
          onEscape: { cancelEdit() }
        )
        .frame(width: frameWidth, height: displayBounds.height)
        .background(
          RoundedRectangle(cornerRadius: 2)
            .stroke(Color.accentColor.opacity(0.6), lineWidth: 1)
            .background(
              RoundedRectangle(cornerRadius: 2)
                .fill(Color.primary.opacity(0.05))
            )
        )
        .position(
          x: displayBounds.minX + frameWidth / 2,
          y: displayBounds.minY + displayBounds.height / 2
        )
        .onAppear {
          editingText = currentText
        }
        .onChange(of: editingText) { _, newValue in
          state.updateAnnotationText(id: editingId, text: newValue)
        }
        .id(editingId)
      }
    }
  }

  /// Convert image bounds to display coordinates (Y-flip for SwiftUI).
  private func calculateDisplayBounds(_ imageBounds: CGRect) -> CGRect {
    let scaledX = imageBounds.origin.x * scale
    let scaledWidth = imageBounds.width * scale
    let scaledHeight = imageBounds.height * scale
    let flippedY = (imageSize.height - imageBounds.origin.y - imageBounds.height) * scale

    return CGRect(x: scaledX, y: flippedY, width: scaledWidth, height: scaledHeight)
  }

  private func commitEdit(id: UUID) {
    guard state.editingTextAnnotationId == id else { return }
    let trimmedText = editingText.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmedText.isEmpty {
      state.saveState()
      state.removeAnnotation(id: id)
    } else {
      state.saveState()
      state.updateAnnotationText(id: id, text: trimmedText)
    }
    state.editingTextAnnotationId = nil
    state.bumpRevision()
  }

  private func cancelEdit() {
    if let editingId = state.editingTextAnnotationId,
       let annotation = state.annotations.first(where: { $0.id == editingId }),
       case .text(let text) = annotation.type,
       text.isEmpty
    {
      state.removeAnnotation(id: editingId)
    }
    state.editingTextAnnotationId = nil
    state.bumpRevision()
  }
}

// MARK: - AppKit NSTextField wrapper

/// NSViewRepresentable wrapping NSTextField for pixel-perfect text alignment
/// with the CG annotation renderer. Both use the same NSFont, eliminating
/// the layout mismatch between SwiftUI TextField and NSString.draw(at:).
private struct NativeAnnotationTextField: NSViewRepresentable {
  @Binding var text: String
  let font: NSFont
  let textColor: NSColor
  let horizontalInset: CGFloat
  let onCommit: () -> Void
  let onEscape: () -> Void

  func makeNSView(context: Context) -> AnnotationNSTextField {
    let field = AnnotationNSTextField()
    field.horizontalInset = horizontalInset
    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.font = font
    field.textColor = textColor
    field.alignment = .left
    field.stringValue = text
    field.cell?.wraps = false
    field.cell?.isScrollable = true
    field.delegate = context.coordinator

    // Focus after the view is in the window hierarchy
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
      field.window?.makeFirstResponder(field)
    }
    return field
  }

  func updateNSView(_ nsView: AnnotationNSTextField, context: Context) {
    if !context.coordinator.isEditing, nsView.stringValue != text {
      nsView.stringValue = text
    }
    nsView.font = font
    nsView.textColor = textColor
    nsView.horizontalInset = horizontalInset
  }

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: NativeAnnotationTextField
    var isEditing = false

    init(_ parent: NativeAnnotationTextField) { self.parent = parent }

    func controlTextDidChange(_ obj: Notification) {
      guard let field = obj.object as? NSTextField else { return }
      isEditing = true
      parent.text = field.stringValue
      isEditing = false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
      parent.onCommit()
    }

    func control(
      _ control: NSControl, textView: NSTextView,
      doCommandBy selector: Selector
    ) -> Bool {
      if selector == #selector(NSResponder.insertNewline(_:)) {
        parent.onCommit()
        return true
      }
      if selector == #selector(NSResponder.cancelOperation(_:)) {
        parent.onEscape()
        return true
      }
      return false
    }
  }
}

// MARK: - Custom NSTextField with controlled text insets

/// NSTextField subclass with configurable horizontal inset to match
/// the annotation renderer's text padding exactly.
final class AnnotationNSTextField: NSTextField {
  var horizontalInset: CGFloat = 0

  override class var cellClass: AnyClass? {
    get { AnnotationTextFieldCell.self }
    set {}
  }
}

/// Cell subclass that controls the drawing rect to match renderer padding.
final class AnnotationTextFieldCell: NSTextFieldCell {
  override func drawingRect(forBounds rect: NSRect) -> NSRect {
    let inset = (controlView as? AnnotationNSTextField)?.horizontalInset ?? 0
    return rect.insetBy(dx: inset, dy: 0)
  }
}
