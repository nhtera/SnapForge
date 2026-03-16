import SwiftUI

/// Bottom bar for video editor with Cancel and Convert buttons.
struct VideoEditorBottomBar: View {
    var onCancel: () -> Void
    var onConvert: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)

                Spacer()

                Button("Convert", action: onConvert)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: [.command])
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.md)
        }
    }
}
