import SwiftUI

/// Design tokens for consistent styling across SnapForge.
enum DesignTokens {
    // MARK: - Spacing
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Corner Radius
    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let full: CGFloat = 999
    }

    // MARK: - Animation
    enum Animation {
        static let fast = SwiftUI.Animation.easeInOut(duration: 0.15)
        static let normal = SwiftUI.Animation.easeInOut(duration: 0.25)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.4)
        static let spring = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.7)
    }

    // MARK: - Shadows
    enum Shadow {
        static let sm = (color: Color.black.opacity(0.1), radius: CGFloat(4), y: CGFloat(2))
        static let md = (color: Color.black.opacity(0.15), radius: CGFloat(8), y: CGFloat(4))
        static let lg = (color: Color.black.opacity(0.2), radius: CGFloat(16), y: CGFloat(8))
    }

    // MARK: - Selection colors
    enum SelectionColors {
        static let primary = Color.accentColor
        static let dimBackground = Color.black.opacity(0.3)
        static let highlight = Color.accentColor.opacity(0.2)
    }
}
