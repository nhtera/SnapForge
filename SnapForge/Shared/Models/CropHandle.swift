import Foundation

/// Handle types for crop operations.
enum CropHandle: String, CaseIterable {
    case topLeft, top, topRight
    case left, right
    case bottomLeft, bottom, bottomRight
    case body

    static var corners: [CropHandle] {
        [.topLeft, .topRight, .bottomLeft, .bottomRight]
    }

    static var edges: [CropHandle] {
        [.top, .bottom, .left, .right]
    }
}
