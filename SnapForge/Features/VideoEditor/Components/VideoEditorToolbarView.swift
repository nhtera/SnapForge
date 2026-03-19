import SwiftUI

/// Top toolbar for video editor window with undo/redo, filename, and sidebar toggles.
struct VideoEditorToolbarView: View {
    @Bindable var state: VideoEditorState

    var body: some View {
        HStack(spacing: 0) {
            leftSection
            Spacer()
            centerSection
            Spacer()
            rightSection
        }
        .frame(height: 40)
        .padding(.horizontal, DesignTokens.Spacing.md)
    }

    // MARK: - Left Section

    private var leftSection: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            // Undo
            toolbarButton(
                label: "Undo",
                icon: "arrow.uturn.backward",
                action: state.undo,
                isActive: false,
                isDisabled: !state.canUndo,
                shortcut: "z",
                modifiers: [.command],
                help: "Undo (⌘Z)"
            )

            // Redo
            toolbarButton(
                label: "Redo",
                icon: "arrow.uturn.forward",
                action: state.redo,
                isActive: false,
                isDisabled: !state.canRedo,
                shortcut: "z",
                modifiers: [.command, .shift],
                help: "Redo (⌘⇧Z)"
            )

            Divider()
                .frame(height: 20)

            // Open in Finder
            toolbarButton(
                label: "Open in Finder",
                icon: "folder",
                action: state.openInFinder,
                help: "Open in Finder"
            )

            // Video Info toggle
            toolbarButton(
                label: "Video Info",
                icon: state.isVideoInfoSidebarVisible ? "info.circle.fill" : "info.circle",
                action: state.toggleVideoInfoSidebar,
                isActive: state.isVideoInfoSidebarVisible,
                shortcut: "i",
                modifiers: [.command],
                help: state.isVideoInfoSidebarVisible ? "Hide Video Info (⌘I)" : "Show Video Info (⌘I)"
            )
        }
    }

    // MARK: - Center Section

    private var centerSection: some View {
        Text(state.filename)
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: 300)
    }

    // MARK: - Right Section

    private var rightSection: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            // Right sidebar toggle (video only — GIF has no background settings)
            if !state.isGIF {
                toolbarButton(
                    label: "Sidebar",
                    icon: "sidebar.right",
                    action: state.toggleRightSidebar,
                    isActive: state.isRightSidebarVisible,
                    shortcut: ".",
                    modifiers: [.command],
                    help: state.isRightSidebarVisible ? "Hide Sidebar (⌘.)" : "Show Sidebar (⌘.)"
                )
            }

            // Unsaved changes indicator
            if state.hasUnsavedChanges {
                Divider()
                    .frame(height: 20)

                HStack(spacing: 4) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(.orange)
                    Text("Unsaved")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Toolbar Button Factory

    @ViewBuilder
    private func toolbarButton(
        label: String,
        icon: String,
        action: @escaping () -> Void,
        isActive: Bool = false,
        isDisabled: Bool = false,
        help: String = ""
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(isActive ? Color.accentColor : .primary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? Color.accentColor.opacity(0.15) : Color.white.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .help(help)
    }

    @ViewBuilder
    private func toolbarButton(
        label: String,
        icon: String,
        action: @escaping () -> Void,
        isActive: Bool = false,
        isDisabled: Bool = false,
        shortcut: KeyEquivalent,
        modifiers: EventModifiers,
        help: String = ""
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(isActive ? Color.accentColor : .primary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? Color.accentColor.opacity(0.15) : Color.white.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .keyboardShortcut(shortcut, modifiers: modifiers)
        .help(help)
    }
}
