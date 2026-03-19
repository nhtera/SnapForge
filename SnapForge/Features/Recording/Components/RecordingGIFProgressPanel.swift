import AppKit
import SwiftUI

/// Floating HUD panel showing GIF conversion progress
@MainActor
final class RecordingGIFProgressPanel {
    private var window: NSPanel?
    private var progressValue: Double = 0

    func show() {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 280, height: 70),
            styleMask: [.titled, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Converting to GIF..."
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.center()
        panel.contentView = NSHostingView(rootView: GIFProgressContentView(progress: 0))
        panel.orderFrontRegardless()
        window = panel
    }

    func update(framesProcessed: Int, totalFrames: Int) {
        progressValue = totalFrames > 0 ? Double(framesProcessed) / Double(totalFrames) : 0
        if let hostingView = window?.contentView as? NSHostingView<GIFProgressContentView> {
            hostingView.rootView = GIFProgressContentView(progress: progressValue)
        }
    }

    func dismiss() {
        window?.close()
        window = nil
    }
}

/// SwiftUI content for GIF progress panel
struct GIFProgressContentView: View {
    let progress: Double

    var body: some View {
        VStack(spacing: 8) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
            Text("\(Int(progress * 100))% — Converting to GIF")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
