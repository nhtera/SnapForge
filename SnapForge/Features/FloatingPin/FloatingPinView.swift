import SwiftUI

/// Floating pinned screenshot — stays on top of all windows.
struct FloatingPinView: View {
    let image: NSImage
    @State private var pinOpacity: Double = 1.0
    @State private var isLocked = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar (visible on hover)
            HStack(spacing: 8) {
                // Opacity slider
                Slider(value: $pinOpacity, in: 0.2...1.0)
                    .frame(width: 80)

                // Lock toggle
                Button(action: { isLocked.toggle() }) {
                    Image(systemName: isLocked ? "lock.fill" : "lock.open")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help(isLocked ? "Unlock (click-through disabled)" : "Lock (enable click-through)")

                Spacer()

                // Close
                Button(action: {
                    // Close this pin window
                    NSApp.keyWindow?.close()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(8)
            .background(.ultraThinMaterial)

            // Image
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
        .opacity(pinOpacity)
    }
}
