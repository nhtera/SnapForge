import SwiftUI

// MARK: - Recording Area Border View (click-through overlay)

/// Just the area highlight border — rendered in a click-through window.
struct RecordingBorderView: View {
    let isPreRecord: Bool

    @State private var isBlinking = true

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .strokeBorder(
                isPreRecord
                    ? Color.accentColor
                    : Color.red.opacity(isBlinking ? 0.9 : 0.5),
                style: isPreRecord
                    ? StrokeStyle(lineWidth: 2, dash: [8, 4])
                    : StrokeStyle(lineWidth: 2),
                antialiased: true
            )
            .animation(.easeInOut(duration: 0.8).repeatForever(), value: isBlinking)
            .onAppear { isBlinking = true }
    }
}

// MARK: - First-Mouse Hosting View

/// Custom NSHostingView that accepts the first mouse click without requiring window activation.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
