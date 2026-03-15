import SwiftUI
import AppKit

/// State for the scroll capture toolbar
enum ScrollCaptureState: Equatable {
    case ready
    case capturing
    case autoScrolling
    case done
}

/// Floating toolbar for scroll capture — CleanShotX-style design.
struct ScrollCaptureToolbarView: View {
    let state: ScrollCaptureState
    let frameCount: Int
    let onStartCapture: () -> Void
    let onCaptureFrame: () -> Void
    let onAutoScroll: () -> Void
    let onPauseAutoScroll: () -> Void
    let onCancel: () -> Void
    let onDone: () -> Void
    let onHelp: () -> Void

    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 0) {
            switch state {
            case .ready:
                readyContent

            case .capturing:
                capturingContent

            case .autoScrolling:
                autoScrollingContent

            case .done:
                doneContent
            }
        }
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThickMaterial)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        )
    }

    // MARK: - Ready State

    private var readyContent: some View {
        HStack(spacing: 0) {
            toolButton(
                title: "Start Capture",
                icon: "play.fill",
                color: .white,
                bgColor: .accentColor,
                action: onStartCapture
            )

            toolSeparator

            toolButton(
                title: "Cancel",
                icon: "xmark",
                color: .secondary,
                action: onCancel
            )

            toolSeparator

            helpButton
        }
    }

    // MARK: - Capturing State (Manual mode)

    private var capturingContent: some View {
        HStack(spacing: 0) {
            // Frame counter
            HStack(spacing: 4) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 11, weight: .medium))
                Text("\(frameCount)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(.blue)
            .padding(.horizontal, 14)

            toolSeparator

            // Manual capture button
            toolButton(
                title: "Capture Frame",
                icon: "camera.fill",
                color: .primary,
                action: onCaptureFrame
            )

            toolSeparator

            // Auto-scroll button
            toolButton(
                title: "Auto-Scroll",
                icon: "arrow.down.circle.fill",
                color: .blue,
                action: onAutoScroll
            )

            toolSeparator

            toolButton(
                title: "Done",
                icon: "checkmark.circle.fill",
                color: .green,
                action: onDone
            )

            toolSeparator

            toolButton(
                title: "Cancel",
                icon: "xmark",
                color: .secondary,
                action: onCancel
            )
        }
    }

    // MARK: - Auto-Scrolling State

    private var autoScrollingContent: some View {
        HStack(spacing: 0) {
            // Frame counter
            HStack(spacing: 4) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 11, weight: .medium))
                Text("\(frameCount)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(.blue)
            .padding(.horizontal, 14)

            toolSeparator

            // Pulsing recording indicator
            HStack(spacing: 5) {
                Circle()
                    .fill(.red)
                    .frame(width: 7, height: 7)
                    .scaleEffect(isPulsing ? 1.3 : 0.7)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isPulsing)
                    .onAppear { isPulsing = true }
                    .onDisappear { isPulsing = false }

                Text("Scrolling…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)

            toolSeparator

            toolButton(
                title: "Pause",
                icon: "pause.fill",
                color: .orange,
                action: onPauseAutoScroll
            )

            toolSeparator

            toolButton(
                title: "Done",
                icon: "checkmark.circle.fill",
                color: .green,
                action: onDone
            )

            toolSeparator

            toolButton(
                title: "Cancel",
                icon: "xmark",
                color: .secondary,
                action: onCancel
            )
        }
    }

    // MARK: - Done State

    private var doneContent: some View {
        toolButton(
            title: "Done",
            icon: "checkmark.circle.fill",
            color: .green,
            action: onDone
        )
    }

    // MARK: - Shared Components

    private func toolButton(
        title: String,
        icon: String,
        color: Color,
        bgColor: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(bgColor != nil ? .white : color)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(bgColor ?? .clear)
        }
        .buttonStyle(.plain)
    }

    private var helpButton: some View {
        Button(action: onHelp) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var toolSeparator: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 1, height: 20)
    }
}

// MARK: - Clickable Panel

/// Custom NSPanel that can become key for button interaction.
final class ClickablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func mouseDown(with event: NSEvent) {
        makeKey()
        super.mouseDown(with: event)
    }
}

/// Custom NSHostingView that accepts first mouse click in non-key windows.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Toolbar Panel

/// NSPanel wrapper — creates panel once and updates rootView for state changes.
@MainActor
final class ScrollCaptureToolbarPanel {

    private var panel: ClickablePanel?
    private var hostingView: FirstClickHostingView<ScrollCaptureToolbarView>?
    private var isShowing = false

    /// Expose window number for capture exclusion
    var windowNumber: Int? { panel?.windowNumber }

    func show(
        below captureRect: CGRect,
        state: ScrollCaptureState,
        frameCount: Int,
        onStartCapture: @escaping () -> Void,
        onCaptureFrame: @escaping () -> Void,
        onAutoScroll: @escaping () -> Void,
        onPauseAutoScroll: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onDone: @escaping () -> Void,
        onHelp: @escaping () -> Void
    ) {
        let toolbarView = ScrollCaptureToolbarView(
            state: state,
            frameCount: frameCount,
            onStartCapture: onStartCapture,
            onCaptureFrame: onCaptureFrame,
            onAutoScroll: onAutoScroll,
            onPauseAutoScroll: onPauseAutoScroll,
            onCancel: onCancel,
            onDone: onDone,
            onHelp: onHelp
        )

        // If panel already exists, just update the rootView
        if isShowing, let hostingView {
            hostingView.rootView = toolbarView

            // Resize panel to fit new content size
            let fittingSize = hostingView.fittingSize
            if let panel {
                var frame = panel.frame
                let oldMidX = frame.midX
                frame.size = fittingSize
                frame.origin.x = oldMidX - fittingSize.width / 2  // Keep centered
                panel.setFrame(frame, display: true)
            }
            return
        }

        let hosting = FirstClickHostingView(rootView: toolbarView)
        hosting.frame = NSRect(x: 0, y: 0, width: 500, height: 44)
        let fittingSize = hosting.fittingSize

        // Position centered below the capture rect (CG → NS coordinates)
        let screenHeight = NSScreen.main?.frame.height ?? 1080
        let toolbarX = captureRect.midX - fittingSize.width / 2
        let toolbarY = screenHeight - captureRect.maxY - fittingSize.height - 16

        let panelFrame = NSRect(
            x: toolbarX,
            y: max(toolbarY, 40),
            width: fittingSize.width,
            height: fittingSize.height
        )

        let newPanel = ClickablePanel(
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
        newPanel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        newPanel.isFloatingPanel = true

        newPanel.contentView = hosting
        newPanel.makeKeyAndOrderFront(nil)

        self.panel = newPanel
        self.hostingView = hosting
        self.isShowing = true
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        isShowing = false
    }
}
