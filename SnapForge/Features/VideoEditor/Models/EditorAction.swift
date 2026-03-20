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

    /// Return the inverse action (swap old/new values) for undo/redo symmetry
    var inverted: EditorAction {
        switch self {
        case .trimStart(let old, let new):
            return .trimStart(old: new, new: old)
        case .trimEnd(let old, let new):
            return .trimEnd(old: new, new: old)
        case .toggleMute(let old, let new):
            return .toggleMute(old: new, new: old)
        case .updateBackground(let oldS, let newS, let oldP, let newP,
                               let oldSh, let newSh, let oldC, let newC):
            return .updateBackground(
                oldStyle: newS, newStyle: oldS,
                oldPadding: newP, newPadding: oldP,
                oldShadow: newSh, newShadow: oldSh,
                oldCorner: newC, newCorner: oldC
            )
        case .gifTrimStart(let old, let new):
            return .gifTrimStart(old: new, new: old)
        case .gifTrimEnd(let old, let new):
            return .gifTrimEnd(old: new, new: old)
        }
    }
}
