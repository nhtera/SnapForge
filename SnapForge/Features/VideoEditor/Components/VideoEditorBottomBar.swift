import SwiftUI

/// Bottom bar for video editor with Cancel and Convert/Save buttons.
struct VideoEditorBottomBar: View {
    var isGIF: Bool = false
    var onCancel: () -> Void
    var onConvert: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)

                Spacer()

                Button(isGIF ? "Save" : "Convert", action: onConvert)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: [.command])
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.md)
        }
    }
}
