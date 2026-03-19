import AppKit
import SwiftUI

/// Manages an inline NSTextField on the annotation canvas for text input.
/// Shows at click point, commits on Enter, dismisses on Escape.
/// Auto-resizes width as user types. Supports editing existing text annotations.
@MainActor
final class RecordingAnnotationTextOverlay: NSObject, NSTextFieldDelegate {
    private var textField: NSTextField?
    /// Stored origin for the annotation bounds (matches text field frame origin)
    private var fieldOrigin: CGPoint = .zero
    private weak var state: RecordingAnnotationState?
    private weak var parentView: NSView?
    /// Called when new text is committed (text, bounds origin)
    var onCommit: ((String, CGPoint) -> Void)?
    /// Called when editing an existing annotation (annotationId, newText)
    var onEditCommit: ((UUID, String) -> Void)?
    private var editingAnnotationId: UUID?
    /// Font size used for current field (may differ from state when editing)
    private var currentFontSize: CGFloat = 20

    private static let minWidth: CGFloat = 80
    private static let maxWidth: CGFloat = 500
    private static let padding: CGFloat = 4

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
        let height = fontSize + Self.padding * 2 + 4
        // Place text field so the text baseline aligns near the click point
        let frameOrigin = CGPoint(x: point.x, y: point.y - Self.padding)

        let field = createField(fontSize: fontSize, color: NSColor(state.strokeColor))
        field.frame = CGRect(x: frameOrigin.x, y: frameOrigin.y, width: Self.minWidth, height: height)

        view.addSubview(field)
        view.window?.makeFirstResponder(field)
        textField = field
        fieldOrigin = frameOrigin
    }

    /// Show text field pre-filled for editing an existing text annotation
    func showForEditing(annotationId: UUID, text: String, at boundsOrigin: CGPoint, fontSize: CGFloat, color: NSColor, in view: NSView) {
        dismiss()
        parentView = view
        editingAnnotationId = annotationId
        currentFontSize = fontSize

        let height = fontSize + Self.padding * 2 + 4
        let textWidth = measureTextWidth(text, fontSize: fontSize)

        let field = createField(fontSize: fontSize, color: color)
        field.stringValue = text
        field.frame = CGRect(x: boundsOrigin.x, y: boundsOrigin.y, width: max(Self.minWidth, textWidth + 16), height: height)

        view.addSubview(field)
        view.window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
        textField = field
        fieldOrigin = boundsOrigin
    }

    func commit() {
        guard let field = textField else { return }
        let text = String(field.stringValue.prefix(200))
        if !text.isEmpty {
            if let editId = editingAnnotationId {
                onEditCommit?(editId, text)
            } else {
                onCommit?(text, fieldOrigin)
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
        // Subtle rounded corners
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
