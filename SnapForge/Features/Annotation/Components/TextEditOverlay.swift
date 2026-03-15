import SwiftUI

/// Overlay for editing text annotations inline on the canvas.
/// Handles coordinate conversion (AppKit bottom-left → SwiftUI top-left)
/// and focus management for reliable text input.
struct TextEditOverlay: View {
  var state: AnnotateState
  let scale: CGFloat
  let imageSize: CGSize

  @State private var editingText: String = ""
  @FocusState private var isFocused: Bool

  // MARK: - Constants

  private let minTextFieldWidth: CGFloat = 60
  private let textPadding: CGFloat = 4

  var body: some View {
    ZStack {
      if let editingId = state.editingTextAnnotationId,
         let annotation = state.annotations.first(where: { $0.id == editingId }),
         case .text(let currentText) = annotation.type
      {
        let displayBounds = calculateDisplayBounds(annotation.bounds)
        let fontSize = max(annotation.properties.fontSize * scale, 10)

        // Text input field positioned exactly at annotation bounds.
        // .id(editingId) forces SwiftUI to RECREATE the TextField when
        // editingId changes, resetting @State editingText and re-triggering
        // onAppear. Without this, switching from one text to another in a
        // single mouseDown reuses the view and @State retains old text.
        TextField("", text: $editingText)
          .textFieldStyle(.plain)
          .font(.system(size: fontSize))
          .foregroundStyle(annotation.properties.strokeColor)
          .multilineTextAlignment(.leading)
          .frame(
            width: max(displayBounds.width, minTextFieldWidth),
            height: displayBounds.height,
            alignment: .leading
          )
          .padding(textPadding)
          .background(
            // Subtle editing indicator — transparent with light border
            RoundedRectangle(cornerRadius: 2)
              .stroke(Color.accentColor.opacity(0.6), lineWidth: 1)
              .background(
                RoundedRectangle(cornerRadius: 2)
                  .fill(Color.primary.opacity(0.05))
              )
          )
          .focused($isFocused)
          .position(
            x: displayBounds.minX + max(displayBounds.width, minTextFieldWidth) / 2,
            y: displayBounds.minY + displayBounds.height / 2
          )
          .onAppear {
            editingText = currentText
            // Delay focus to ensure view is ready
            Task { @MainActor in
              try? await Task.sleep(for: .milliseconds(50))
              isFocused = true
            }
          }
          .onSubmit {
            commitEdit(id: editingId)
          }
          .onExitCommand {
            cancelEdit()
          }
          .onChange(of: isFocused) { _, newValue in
            if !newValue && state.editingTextAnnotationId == editingId {
              commitEdit(id: editingId)
            }
          }
          // Live-sync text to annotation model on every keystroke.
          // This ensures the annotation always has the latest text,
          // so DrawingCanvasNSView can safely clear editingTextAnnotationId
          // (e.g. when clicking elsewhere to create a new text annotation)
          // without losing uncommitted text.
          .onChange(of: editingText) { _, newValue in
            state.updateAnnotationText(id: editingId, text: newValue)
          }
          .id(editingId)
      }
    }
  }

  /// Convert image bounds to display coordinates.
  /// The parent view supplies a frame that matches the full image display size.
  /// 1. Scale the bounds
  /// 2. Flip Y axis (AppKit bottom-left origin → SwiftUI top-left origin)
  private func calculateDisplayBounds(_ imageBounds: CGRect) -> CGRect {
    let scaledX = imageBounds.origin.x * scale
    let scaledWidth = imageBounds.width * scale
    let scaledHeight = imageBounds.height * scale

    // Flip Y axis: AppKit y=0 is bottom, SwiftUI y=0 is top
    let flippedY = (imageSize.height - imageBounds.origin.y - imageBounds.height) * scale

    return CGRect(
      x: scaledX,
      y: flippedY,
      width: scaledWidth,
      height: scaledHeight
    )
  }

  private func commitEdit(id: UUID) {
    let trimmedText = editingText.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmedText.isEmpty {
      // Delete annotation if text is empty
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
    // If it was a new annotation with empty text, delete it
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
