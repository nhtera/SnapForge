import SwiftUI

/// Bottom toolbar shown during crop mode with Cancel and Apply buttons.
struct CropToolbar: View {
    var onCancel: () -> Void
    var onApply: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onCancel) {
                Label("Cancel", systemImage: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])

            Button(action: onApply) {
                Label("Apply Crop", systemImage: "checkmark")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
        }
    }
}
