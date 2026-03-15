import Foundation

enum CaptureMode: String, CaseIterable, Identifiable {
    case area = "Area"
    case window = "Window"
    case fullscreen = "Fullscreen"
    case timedArea = "Self-Timer"
    case ocrCapture = "OCR Capture"
    case scrollCapture = "Scroll Capture"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .area: return "rectangle.dashed"
        case .window: return "macwindow"
        case .fullscreen: return "rectangle.inset.filled"
        case .timedArea: return "timer"
        case .ocrCapture: return "doc.text.viewfinder"
        case .scrollCapture: return "rectangle.expand.vertical"
        }
    }

    var shortcut: String {
        switch self {
        case .area: return "⌘⇧4"
        case .window: return "⌘⇧W"
        case .fullscreen: return "⌘⇧3"
        case .timedArea: return "⌘⇧5"
        case .ocrCapture: return "⌘⇧O"
        case .scrollCapture: return "⌘⇧S"
        }
    }
}
