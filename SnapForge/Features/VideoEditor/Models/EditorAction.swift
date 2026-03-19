import SwiftUI

/// Represents an undoable editor action for the video editor undo/redo system.
enum EditorAction: Equatable {
    case trimStart(old: Double, new: Double)
    case trimEnd(old: Double, new: Double)
    case toggleMute(old: Bool, new: Bool)
    case updateBackground(
        oldStyle: VideoBackgroundStyle, newStyle: VideoBackgroundStyle,
        oldPadding: CGFloat, newPadding: CGFloat,
        oldShadow: CGFloat, newShadow: CGFloat,
        oldCorner: CGFloat, newCorner: CGFloat
    )

    // GIF-specific
    case gifTrimStart(old: Int, new: Int)
    case gifTrimEnd(old: Int, new: Int)
}
