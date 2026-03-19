import SwiftUI

/// Individual tool button in the annotation tool palette.
struct ToolButton: View {
  let tool: AnnotationToolType
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 3) {
        Image(systemName: tool.icon)
          .font(.system(size: 20))
        Text(tool.displayName)
          .font(.system(size: 9))
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, minHeight: 48)
      .foregroundStyle(isSelected ? Color.accentColor : .primary)
      .background(isSelected ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 8))
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .focusable(false)
    .help(tool.displayName)
    .accessibilityIdentifier("annotationTool_\(tool.rawValue)")
  }
}

