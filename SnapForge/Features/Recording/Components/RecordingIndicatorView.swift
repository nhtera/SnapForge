import SwiftUI

// MARK: - Recording Area Border View (click-through overlay)

/// Area highlight border — rendered in a click-through window.
/// Pre-record: always accent+dashed. Active recording: configurable style/color.
struct RecordingBorderView: View {
    let isPreRecord: Bool
    var borderConfig: RecordingBorderConfiguration?

    @State private var isBlinking = true

    var body: some View {
        if isPreRecord {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4]),
                    antialiased: true
                )
        } else {
            let config = borderConfig ?? RecordingBorderConfiguration()
            borderShape(config)
                .animation(.easeInOut(duration: 0.8).repeatForever(), value: isBlinking)
                .onAppear { isBlinking = true }
        }
    }

    /// Active recording border — style varies, animation shared
    @ViewBuilder
    private func borderShape(_ config: RecordingBorderConfiguration) -> some View {
        switch config.style {
        case .solid:
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(config.color.opacity(isBlinking ? 0.9 : 0.5),
                              style: StrokeStyle(lineWidth: 2), antialiased: true)
        case .dashed:
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(config.color.opacity(isBlinking ? 0.9 : 0.5),
                              style: StrokeStyle(lineWidth: 2, dash: [8, 4]), antialiased: true)
        case .glow:
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(config.color.opacity(isBlinking ? 0.9 : 0.5),
                              style: StrokeStyle(lineWidth: 2), antialiased: true)
                .shadow(color: config.color.opacity(0.5), radius: 6)
        case .none:
            Color.clear
        }
    }
}

// MARK: - First-Mouse Hosting View

/// Custom NSHostingView that accepts the first mouse click without requiring window activation.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
