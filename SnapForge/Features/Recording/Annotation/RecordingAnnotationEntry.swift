import Foundation

/// Wrapper around AnnotationItem with recording lifecycle metadata
struct RecordingAnnotationEntry: Identifiable, Equatable {
    let id: UUID
    let item: AnnotationItem
    let createdAt: Date
    let createdByTool: AnnotationToolType
    var opacity: Double

    init(item: AnnotationItem, tool: AnnotationToolType) {
        self.id = item.id
        self.item = item
        self.createdAt = Date()
        self.createdByTool = tool
        self.opacity = 1.0
    }

    static func == (lhs: RecordingAnnotationEntry, rhs: RecordingAnnotationEntry) -> Bool {
        lhs.id == rhs.id && lhs.opacity == rhs.opacity
    }
}
