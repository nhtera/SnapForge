import SwiftUI
import AppKit

// MARK: - Help Page Data

struct HelpPage {
    let title: String
    let subtitle: String
    let items: [HelpItem]
}

struct HelpItem {
    let icon: String
    let description: String
    let isCorrect: Bool
}

// MARK: - Help Popup View

struct ScrollCaptureHelpView: View {
    @State private var currentPage = 0
    let onDismiss: () -> Void

    private let pages: [HelpPage] = [
        HelpPage(
            title: "How to select an area?",
            subtitle: "Only scrollable content should be selected.\nAny non-moving parts or scroll bar should not be present in your selection.",
            items: [
                HelpItem(icon: "checkmark.circle.fill", description: "Select only the content area", isCorrect: true),
                HelpItem(icon: "xmark.circle.fill", description: "Don't include the sidebar", isCorrect: false),
                HelpItem(icon: "xmark.circle.fill", description: "Don't include the scroll bar", isCorrect: false)
            ]
        ),
        HelpPage(
            title: "Slowly scroll down the content",
            subtitle: "You'll see a preview of your screenshot updated in real time.\nScrolling too fast might result in breaking the capture process.",
            items: [
                HelpItem(icon: "checkmark.circle.fill", description: "Scroll slowly and steadily", isCorrect: true),
                HelpItem(icon: "xmark.circle.fill", description: "Don't scroll too fast", isCorrect: false)
            ]
        ),
        HelpPage(
            title: "Troubleshooting",
            subtitle: "The following conditions may break the scrolling capture:",
            items: [
                HelpItem(icon: "exclamationmark.triangle.fill", description: "Selected area contains animations or videos", isCorrect: false),
                HelpItem(icon: "exclamationmark.triangle.fill", description: "Not doing a fully vertical scrolling", isCorrect: false),
                HelpItem(icon: "exclamationmark.triangle.fill", description: "Scrolling too fast", isCorrect: false),
                HelpItem(icon: "exclamationmark.triangle.fill", description: "Starting to scroll up instead of down", isCorrect: false)
            ]
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Content
            pageContent(pages[currentPage])
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.2), value: currentPage)

            // Footer
            footerView
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
        }
        .frame(width: 520, height: 440)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                .fill(.ultraThickMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
    }

    // MARK: - Page Content

    @ViewBuilder
    private func pageContent(_ page: HelpPage) -> some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 8)

            // Title
            Text(page.title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            // Subtitle
            Text(page.subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 32)

            Spacer().frame(height: 4)

            // Items
            if currentPage == 2 {
                // Troubleshooting: list layout
                troubleshootingItems(page.items)
            } else {
                // Pages 1-2: card layout
                cardItems(page.items)
            }

            Spacer()
        }
    }

    // MARK: - Card Items (Pages 1-2)

    private func cardItems(_ items: [HelpItem]) -> some View {
        HStack(spacing: 16) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(spacing: 12) {
                    // Illustration card
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                        .fill(item.isCorrect ?
                              Color.green.opacity(0.08) :
                              Color.red.opacity(0.08))
                        .frame(height: 120)
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: item.isCorrect ? "doc.text.image" : "doc.text.image")
                                    .font(.system(size: 32))
                                    .foregroundStyle(item.isCorrect ? .green.opacity(0.6) : .red.opacity(0.4))

                                // Selection indicator
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                    .stroke(item.isCorrect ? .blue : .blue, style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                                    .frame(width: item.isCorrect ? 60 : 80, height: 50)
                                    .overlay(
                                        VStack(spacing: 3) {
                                            ForEach(0..<3, id: \.self) { _ in
                                                RoundedRectangle(cornerRadius: 1)
                                                    .fill(.secondary.opacity(0.4))
                                                    .frame(height: 4)
                                                    .padding(.horizontal, 8)
                                            }
                                        }
                                    )
                            }
                        )

                    // Status icon
                    Image(systemName: item.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(item.isCorrect ? .green : .red)

                    // Description
                    Text(item.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 28)
    }

    // MARK: - Troubleshooting Items (Page 3)

    private func troubleshootingItems(_ items: [HelpItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)

                    Text(item.description)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(.horizontal, 48)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer

    private var footerView: some View {
        VStack(spacing: 16) {
            // Page dots
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                        .scaleEffect(index == currentPage ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: currentPage)
                        .onTapGesture { currentPage = index }
                }
            }

            // Navigation button
            Button(action: {
                if currentPage < pages.count - 1 {
                    withAnimation { currentPage += 1 }
                } else {
                    onDismiss()
                }
            }) {
                Text(currentPage < pages.count - 1 ? "Next" : "Start capturing")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 160, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .fill(Color.accentColor)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Help Popup Panel

@MainActor
final class ScrollCaptureHelpPanel {

    private var panel: ClickablePanel?

    /// Expose window number for capture exclusion
    var windowNumber: Int? { panel?.windowNumber }

    func show(onDismiss: @escaping () -> Void) {
        print("📖 ScrollCaptureHelpPanel.show() called")

        // If already showing, just bring to front
        if let panel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let helpView = ScrollCaptureHelpView(onDismiss: { [weak self] in
            self?.dismiss()
            onDismiss()
        })

        // Add a close button wrapper
        let wrappedView = ZStack(alignment: .topLeading) {
            helpView
            Button(action: { [weak self] in
                self?.dismiss()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(12)
        }

        let hosting = FirstClickHostingView(rootView: wrappedView)
        let panelSize = CGSize(width: 520, height: 440)
        hosting.frame = NSRect(origin: .zero, size: panelSize)

        // Center on screen
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let x = (screen.frame.width - panelSize.width) / 2
        let y = (screen.frame.height - panelSize.height) / 2

        let newPanel = ClickablePanel(
            contentRect: NSRect(x: x, y: y, width: panelSize.width, height: panelSize.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.level = .statusBar + 3
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = true
        newPanel.isReleasedWhenClosed = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        newPanel.isFloatingPanel = true

        newPanel.contentView = hosting
        newPanel.makeKeyAndOrderFront(nil)

        self.panel = newPanel
        print("📖 Help panel created and shown")
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}
