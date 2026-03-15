import SwiftUI
import AppKit

/// Floating preview panel for scroll capture progress.
struct ScrollCapturePreviewView: View {
    let image: NSImage?
    let frameCount: Int

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 6) {
                Image(systemName: "rectangle.expand.vertical")
                    .font(.system(size: 10, weight: .semibold))
                Text("Preview")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if frameCount > 0 {
                    Text("\(frameCount) frames")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()
                .opacity(0.5)

            // Preview content
            if let image {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 178)  // Fixed width minus padding
                            .id("previewImage")
                    }
                    .onChange(of: frameCount) {
                        withAnimation {
                            proxy.scrollTo("previewImage", anchor: .bottom)
                        }
                    }
                }
                .frame(height: min(max(CGFloat(frameCount) * 60, 120), 500))
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 22, weight: .ultraLight))
                        .foregroundStyle(.quaternary)
                    Text("Scroll to capture")
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                }
                .frame(height: 100)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThickMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 5)
    }
}

// MARK: - Preview Panel

@MainActor
final class ScrollCapturePreviewPanel {

    private var panel: NSPanel?
    private var hostingView: NSHostingView<ScrollCapturePreviewView>?

    /// Expose window number for capture exclusion
    var windowNumber: Int? { panel?.windowNumber }

    func show(toRightOf captureRect: CGRect, image: NSImage?, frameCount: Int) {
        let previewView = ScrollCapturePreviewView(image: image, frameCount: frameCount)
        let hosting = NSHostingView(rootView: previewView)
        hosting.frame = NSRect(x: 0, y: 0, width: 200, height: 200)

        let fittingSize = hosting.fittingSize
        let screenHeight = NSScreen.main?.frame.height ?? 1080
        let screenWidth = NSScreen.main?.frame.width ?? 1920
        let previewWidth: CGFloat = max(fittingSize.width, 200)
        let previewHeight: CGFloat = max(fittingSize.height, 140)
        let gap: CGFloat = 12
        let inset: CGFloat = 8

        // Smart positioning: right → left → inside capture area
        let spaceRight = screenWidth - captureRect.maxX
        let spaceLeft = captureRect.minX

        let panelX: CGFloat
        let panelY: CGFloat

        if spaceRight >= previewWidth + gap {
            // Preferred: right of capture area
            panelX = captureRect.maxX + gap
            panelY = screenHeight - captureRect.minY - previewHeight
        } else if spaceLeft >= previewWidth + gap {
            // Fallback: left of capture area
            panelX = captureRect.minX - previewWidth - gap
            panelY = screenHeight - captureRect.minY - previewHeight
        } else {
            // Last resort: inside capture area (top-right corner with inset)
            panelX = captureRect.maxX - previewWidth - inset
            panelY = screenHeight - captureRect.minY - previewHeight - inset
        }

        let panelFrame = NSRect(
            x: panelX,
            y: max(panelY, 40),
            width: previewWidth,
            height: previewHeight
        )

        let newPanel = NSPanel(
            contentRect: panelFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.level = .statusBar + 2
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false
        newPanel.isReleasedWhenClosed = false
        newPanel.ignoresMouseEvents = true
        newPanel.collectionBehavior = [.canJoinAllSpaces, .stationary]

        newPanel.contentView = hosting
        newPanel.orderFrontRegardless()

        self.panel = newPanel
        self.hostingView = hosting
    }

    func update(image: NSImage?, frameCount: Int) {
        let previewView = ScrollCapturePreviewView(image: image, frameCount: frameCount)
        hostingView?.rootView = previewView

        // Resize panel to fit updated content
        if let hosting = hostingView, let panel {
            // Give the hosting view a moment to recalculate
            Task { @MainActor in
                let fittingSize = hosting.fittingSize
                var frame = panel.frame
                // Grow downward from the top anchor
                let topY = frame.origin.y + frame.height
                frame.size.width = max(fittingSize.width, 200)
                frame.size.height = max(fittingSize.height, 140)
                frame.origin.y = topY - frame.size.height
                panel.setFrame(frame, display: true)
            }
        }
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }
}
