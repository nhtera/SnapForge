import Foundation

/// Handle types for resize operations on annotations.
enum ResizeHandle: Equatable {
    case topLeft, topRight, bottomLeft, bottomRight
    case top, bottom, left, right
}
