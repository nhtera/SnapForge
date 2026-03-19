import SwiftUI

/// Constants for recording toolbar layout and sizing
enum RecordingToolbarConstants {
    static let iconSize: CGFloat = 14
    static let buttonSize: CGFloat = 32
    static let toolbarCornerRadius: CGFloat = DesignTokens.Radius.md
    static let groupSpacing: CGFloat = DesignTokens.Spacing.xxs
    static let itemSpacing: CGFloat = DesignTokens.Spacing.xs
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 6
    static let toolbarGap: CGFloat = 20
    static let hoverAnimation = DesignTokens.Animation.fast
}

/// Vertical divider for toolbar groups
struct RecordingToolbarDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.2))
            .frame(width: 1, height: 20)
            .padding(.horizontal, RecordingToolbarConstants.groupSpacing)
    }
}

/// Button style for text action buttons (Record, Stop)
struct TextToolbarButtonStyle: ButtonStyle {
    let backgroundColor: Color
    let foregroundColor: Color

    init(backgroundColor: Color = .red, foregroundColor: Color = .white) {
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(backgroundColor.opacity(configuration.isPressed ? 0.7 : 1.0), in: RoundedRectangle(cornerRadius: 6))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(RecordingToolbarConstants.hoverAnimation, value: configuration.isPressed)
    }
}
