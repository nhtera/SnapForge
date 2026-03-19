import AppKit
import SwiftUI

/// Overlay for editing text annotations inline on the canvas.
/// Uses AppKit NSTextView for multiline support with pixel-perfect
/// alignment with the Core Graphics renderer — both use the same NSFont.
struct TextEditOverlay: View {
  var state: AnnotateState
  let scale: CGFloat
  let imageSize: CGSize

  @State private var editingText: String = ""

  private let minTextFieldWidth: CGFloat = 60

  var body: some View {
    ZStack(alignment: .topLeading) {
      if let editingId = state.editingTextAnnotationId,
         let annotation = state.annotations.first(where: { $0.id == editingId }),
         case .text(let currentText) = annotation.type
      {
        let topLeft = calculateTopLeft(annotation.bounds)
        let fontSize = max(annotation.properties.fontSize * scale, 10)
        let frameWidth = max(annotation.bounds.width * scale, minTextFieldWidth)
        let minHeight = TextAnnotationLayout.minimumHeight(for: fontSize)
        let frameHeight = max(annotation.bounds.height * scale, minHeight)

        NativeAnnotationTextView(
          text: $editingText,
          font: TextAnnotationLayout.font(size: fontSize),
          textColor: NSColor(annotation.properties.strokeColor),
          horizontalInset: TextAnnotationLayout.horizontalPadding * scale,
          verticalInset: TextAnnotationLayout.verticalPadding * scale,
          onCommit: { commitEdit(id: editingId) },
          onEscape: { cancelEdit() }
        )
        .frame(width: frameWidth, height: frameHeight)
        .background(
          RoundedRectangle(cornerRadius: 2)
            .stroke(Color.accentColor.opacity(0.6), lineWidth: 1)
            .background(
              RoundedRectangle(cornerRadius: 2)
                .fill(Color.primary.opacity(0.05))
            )
        )
        .offset(x: topLeft.x, y: topLeft.y)
        .onAppear {
          editingText = currentText
        }
        .onChange(of: editingText) { _, newValue in
          state.updateAnnotationText(id: editingId, text: newValue)
        }
        .id(editingId)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  /// Convert image-space bounds to SwiftUI top-left anchor (Y-flip).
  /// maxY in CG = top of text (first line). This is kept stable by
  /// updateAnnotationText, so the overlay doesn't shift when height grows.
  private func calculateTopLeft(_ imageBounds: CGRect) -> CGPoint {
    let scaledX = imageBounds.origin.x * scale
    // SwiftUI Y = imageSize.height - CG_maxY (top of text in CG coords)
    let topY = (imageSize.height - imageBounds.maxY) * scale
    return CGPoint(x: scaledX, y: topY)
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

// MARK: - AppKit NSTextView wrapper

/// NSViewRepresentable wrapping NSTextView directly (no NSScrollView).
/// Enter inserts newline, Cmd+Enter commits, Escape cancels.
/// Uses the same NSFont as the CG annotation renderer for pixel-perfect alignment.
private struct NativeAnnotationTextView: NSViewRepresentable {
  @Binding var text: String
  let font: NSFont
  let textColor: NSColor
  let horizontalInset: CGFloat
  let verticalInset: CGFloat
  let onCommit: () -> Void
  let onEscape: () -> Void

  func makeNSView(context: Context) -> NSTextView {
    let textView = NSTextView()
    textView.isRichText = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.font = font
    textView.textColor = textColor
    textView.backgroundColor = .clear
    textView.drawsBackground = false
    textView.isEditable = true
    textView.isSelectable = true
    textView.delegate = context.coordinator
    textView.textContainerInset = NSSize(width: horizontalInset, height: verticalInset)
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.widthTracksTextView = true
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width, .height]
    textView.setAccessibilityIdentifier("annotationTextField")
    textView.setAccessibilityElement(true)
    textView.string = text

    // Focus after the view is in the window hierarchy
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
      textView.window?.makeFirstResponder(textView)
    }
    return textView
  }

  func updateNSView(_ textView: NSTextView, context: Context) {
    if !context.coordinator.isUpdating, textView.string != text {
      context.coordinator.isUpdating = true
      let savedRanges = textView.selectedRanges
      textView.string = text
      textView.selectedRanges = savedRanges
      context.coordinator.isUpdating = false
    }
    textView.font = font
    textView.textColor = textColor
    textView.textContainerInset = NSSize(width: horizontalInset, height: verticalInset)
  }

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  class Coordinator: NSObject, NSTextViewDelegate {
    var parent: NativeAnnotationTextView
    var isUpdating = false

    init(_ parent: NativeAnnotationTextView) { self.parent = parent }

    func textDidChange(_ notification: Notification) {
      guard !isUpdating, let textView = notification.object as? NSTextView else { return }
      parent.text = textView.string
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
      // Cmd+Enter = commit
      if selector == #selector(NSResponder.insertNewline(_:)) {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        if flags.contains(.command) {
          parent.onCommit()
          return true
        }
        // Plain Enter = insert newline (default NSTextView behavior)
        return false
      }
      // Escape = cancel
      if selector == #selector(NSResponder.cancelOperation(_:)) {
        parent.onEscape()
        return true
      }
      return false
    }
  }
}
