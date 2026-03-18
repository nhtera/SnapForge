import Foundation

/// Tool types available in annotation editor
enum AnnotationToolType: String, CaseIterable, Identifiable {
  case selection
  case crop
  case rectangle
  case filledRectangle
  case oval
  case arrow
  case line
  case text
  case highlighter
  case blur
  case counter
  case pencil
  case redact
  case ruler

  var id: String { rawValue }

  var icon: String {
    switch self {
    case .selection: return "cursorarrow"
    case .crop: return "crop"
    case .rectangle: return "rectangle"
    case .filledRectangle: return "rectangle.fill"
    case .oval: return "circle"
    case .arrow: return "arrow.up.right"
    case .line: return "line.diagonal"
    case .text: return "character.textbox"
    case .highlighter: return "highlighter"
    case .blur: return "eye.slash"
    case .counter: return "list.number"
    case .pencil: return "pencil"
    case .redact: return "eye.slash.fill"
    case .ruler: return "ruler"
    }
  }

  /// Default keyboard shortcut for this tool
  var defaultShortcut: Character {
    switch self {
    case .selection: return "v"
    case .crop: return "c"
    case .rectangle: return "r"
    case .filledRectangle: return "f"
    case .oval: return "o"
    case .arrow: return "a"
    case .line: return "l"
    case .text: return "t"
    case .highlighter: return "h"
    case .blur: return "b"
    case .counter: return "n"
    case .pencil: return "p"
    case .redact: return "d"
    case .ruler: return "m"
    }
  }

  /// Display name for the tool
  /// Subset of tools available during screen recording
  static let recordingTools: [AnnotationToolType] = [
    .selection, .rectangle, .oval, .arrow, .line, .pencil, .highlighter,
  ]

  var displayName: String {
    switch self {
    case .selection: return "Selection"
    case .crop: return "Crop"
    case .rectangle: return "Rectangle"
    case .filledRectangle: return "Filled Rectangle"
    case .oval: return "Oval"
    case .arrow: return "Arrow"
    case .line: return "Line"
    case .text: return "Text"
    case .highlighter: return "Highlighter"
    case .blur: return "Blur"
    case .counter: return "Counter"
    case .pencil: return "Pencil"
    case .redact: return "Redact"
    case .ruler: return "Ruler"
    }
  }
}
