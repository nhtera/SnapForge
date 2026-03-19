import AppKit
import SwiftUI

/// Manages an inline NSTextField on the annotation canvas for text input.
/// At commit, stores the field frame so the canvas can render text at the exact same position.
@MainActor
final class RecordingAnnotationTextOverlay: NSObject, NSTextFieldDelegate {
    private var textField: NSTextField?
    private weak var state: RecordingAnnotationState?
    private weak var parentView: NSView?
    /// Called when new text is committed (text, field frame in view coords)
    var onCommit: ((String, CGRect) -> Void)?
    /// Called when editing an existing annotation (annotationId, newText)
    var onEditCommit: ((UUID, String) -> Void)?
    private var editingAnnotationId: UUID?
    private var currentFontSize: CGFloat = 20

    private static let minWidth: CGFloat = 80
    private static let maxWidth: CGFloat = 500

    init(state: RecordingAnnotationState) {
        self.state = state
        super.init()
    }

    /// Show text field for new text at the given click point
    func show(at point: CGPoint, in view: NSView) {
        dismiss()
        guard let state else { return }
        parentView = view
        editingAnnotationId = nil

        let fontSize = state.selectedFontSize
        currentFontSize = fontSize
        let height = fontSize + 12

        let field = createField(fontSize: fontSize, color: NSColor(state.strokeColor))
        // Center vertically on click point
        field.frame = CGRect(x: point.x, y: point.y - height / 2, width: Self.minWidth, height: height)

        view.addSubview(field)
        view.window?.makeFirstResponder(field)
        textField = field
    }

    /// Show text field pre-filled for editing an existing text annotation
    func showForEditing(annotationId: UUID, text: String, bounds: CGRect, fontSize: CGFloat, color: NSColor, in view: NSView) {
        dismiss()
        parentView = view
        editingAnnotationId = annotationId
        currentFontSize = fontSize

        let height = fontSize + 12
        let textWidth = measureTextWidth(text, fontSize: fontSize)

        let field = createField(fontSize: fontSize, color: color)
        field.stringValue = text
        // Place field at the annotation bounds (bounds IS the field frame from original commit)
        field.frame = CGRect(x: bounds.origin.x, y: bounds.origin.y, width: max(Self.minWidth, textWidth + 16), height: height)

        view.addSubview(field)
        view.window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
        textField = field
    }

    func commit() {
        guard let field = textField else { return }
        let text = String(field.stringValue.prefix(200))
        if !text.isEmpty {
            if let editId = editingAnnotationId {
                onEditCommit?(editId, text)
            } else {
                // Pass the field frame directly — canvas renders text using this frame
                onCommit?(text, field.frame)
            }
        }
        dismiss()
    }

    func dismiss() {
        let view = parentView
        textField?.removeFromSuperview()
        textField = nil
        editingAnnotationId = nil
        if let view {
            view.window?.makeFirstResponder(view)
        }
    }

    var isActive: Bool { textField != nil }
    var currentEditingId: UUID? { editingAnnotationId }

    // MARK: - Private

    private func createField(fontSize: CGFloat, color: NSColor) -> NSTextField {
        let field = NSTextField()
        field.font = .systemFont(ofSize: fontSize)
        field.textColor = color
        field.backgroundColor = NSColor.black.withAlphaComponent(0.25)
        field.drawsBackground = true
        field.isBezeled = false
        field.isBordered = false
        field.focusRingType = .none
        field.isEditable = true
        field.isSelectable = true
        field.placeholderString = "Type text..."
        field.delegate = self
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.wantsLayer = true
        field.layer?.cornerRadius = 3
        return field
    }

    private func measureTextWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize)]
        return (text as NSString).size(withAttributes: attrs).width
    }

    private func autoResize() {
        guard let field = textField else { return }
        let text = field.stringValue
        let textWidth = measureTextWidth(text, fontSize: currentFontSize)
        let newWidth = min(Self.maxWidth, max(Self.minWidth, textWidth + 24))
        var frame = field.frame
        frame.size.width = newWidth
        field.frame = frame
    }

    // MARK: - NSTextFieldDelegate

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commit()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            dismiss()
            return true
        }
        return false
    }

    func controlTextDidChange(_ obj: Notification) {
        autoResize()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if isActive {
            commit()
        }
    }
}
