import Foundation
import SwiftUI

/// Represents a single annotation element on the canvas.
protocol AnnotationItem: Identifiable {
    var id: UUID { get }
    var type: AnnotationType { get }
    var isSelected: Bool { get set }
}

/// Types of annotation tools available.
enum AnnotationType: String, CaseIterable, Identifiable {
    case select = "Select"
    case arrow = "Arrow"
    case line = "Line"
    case rectangle = "Rectangle"
    case ellipse = "Ellipse"
    case text = "Text"
    case pencil = "Pencil"
    case highlighter = "Highlighter"
    case blur = "Blur"
    case pixelate = "Pixelate"
    case spotlight = "Spotlight"
    case counter = "Counter"
    case crop = "Crop"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .pencil: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .blur: return "aqi.medium"
        case .pixelate: return "mosaic"
        case .spotlight: return "light.max"
        case .counter: return "number.circle"
        case .crop: return "crop"
        }
    }
}

/// Concrete annotation: A shape (rectangle, ellipse, etc.)
struct ShapeAnnotation: AnnotationItem {
    let id = UUID()
    let type: AnnotationType
    var rect: CGRect
    var color: Color
    var strokeWidth: CGFloat
    var isFilled: Bool
    var cornerRadius: CGFloat
    var isSelected: Bool = false
}

/// Concrete annotation: Arrow
struct ArrowAnnotation: AnnotationItem {
    let id = UUID()
    var type: AnnotationType = .arrow
    var startPoint: CGPoint
    var endPoint: CGPoint
    var color: Color
    var strokeWidth: CGFloat
    var isCurved: Bool
    var controlPoint: CGPoint?
    var isSelected: Bool = false
}

/// Concrete annotation: Text label
struct TextAnnotation: AnnotationItem {
    let id = UUID()
    let type: AnnotationType = .text
    var position: CGPoint
    var text: String
    var font: NSFont
    var color: Color
    var backgroundColor: Color?
    var style: TextStyle
    var isSelected: Bool = false

    enum TextStyle: String, CaseIterable {
        case plain, callout, boxed, numbered, bold, code, highlight
    }
}

/// Concrete annotation: Pencil drawing (freehand)
struct PencilAnnotation: AnnotationItem {
    let id = UUID()
    var type: AnnotationType = .pencil
    var points: [CGPoint]
    var color: Color
    var strokeWidth: CGFloat
    var isSmoothed: Bool
    var isSelected: Bool = false
}

/// Concrete annotation: Blur/Pixelate region
struct EffectAnnotation: AnnotationItem {
    let id = UUID()
    let type: AnnotationType
    var rect: CGRect
    var intensity: CGFloat
    var isSelected: Bool = false
}

/// Concrete annotation: Counter (numbered circle)
struct CounterAnnotation: AnnotationItem {
    let id = UUID()
    let type: AnnotationType = .counter
    var position: CGPoint
    var number: Int
    var color: Color
    var size: CGFloat
    var isSelected: Bool = false
}
