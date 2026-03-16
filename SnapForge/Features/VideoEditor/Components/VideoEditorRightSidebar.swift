import SwiftUI

/// Tab selection for the right sidebar.
enum VideoEditorSidebarTab: String, CaseIterable {
    case background = "Background"

    var icon: String {
        switch self {
        case .background: "rectangle.on.rectangle"
        }
    }
}

/// Right sidebar container with vertical tab bar.
/// Currently contains Background tab; extensible for Zoom tab in future.
struct VideoEditorRightSidebar: View {
    @Bindable var state: VideoEditorState

    @State private var selectedTab: VideoEditorSidebarTab = .background

    var body: some View {
        HStack(spacing: 0) {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            verticalTabBar
        }
        .frame(width: 280)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .background:
            VideoEditorBackgroundSidebarView(state: state)
        }
    }

    private var verticalTabBar: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            ForEach(VideoEditorSidebarTab.allCases, id: \.rawValue) { tab in
                tabButton(for: tab)
            }

            Spacer()
        }
        .padding(.vertical, DesignTokens.Spacing.sm)
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .frame(width: 44)
    }

    private func tabButton(for tab: VideoEditorSidebarTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = tab
            }
        } label: {
            Image(systemName: tab.icon)
                .font(.system(size: 14))
                .frame(width: 32, height: 32)
                .background(
                    isSelected
                        ? Color.accentColor.opacity(0.2)
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help(tab.rawValue)
    }
}
