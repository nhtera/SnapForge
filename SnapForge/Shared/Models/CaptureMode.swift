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

/// Defines recording modes.
enum RecordingMode: String, CaseIterable, Identifiable {
    case area = "Area"
    case window = "Window"
    case fullscreen = "Fullscreen"

    var id: String { rawValue }
}

/// Supported image export formats.
enum ImageExportFormat: String, CaseIterable, Identifiable {
    case png = "PNG"
    case jpg = "JPG"
    case webp = "WebP"
    case heic = "HEIC"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpg: return "jpg"
        case .webp: return "webp"
        case .heic: return "heic"
        }
    }
}

/// Supported video export formats.
enum VideoExportFormat: String, CaseIterable, Identifiable {
    case mp4 = "MP4"
    case gif = "GIF"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .mp4: return "mp4"
        case .gif: return "gif"
        }
    }
}
