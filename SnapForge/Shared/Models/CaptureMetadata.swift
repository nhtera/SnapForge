import Foundation

/// Persistent metadata for a captured item — stored alongside files as JSON.
struct CaptureMetadata: Codable, Identifiable, Equatable {
  let id: String          // filename as unique key
  var filePath: String
  var tags: [String]
  var ocrText: String?
  var appName: String?
  var date: Date
  var type: String        // "screenshot", "recording", "gif"

  init(
    filePath: String,
    tags: [String] = [],
    ocrText: String? = nil,
    appName: String? = nil,
    date: Date = Date(),
    type: String = "screenshot"
  ) {
    self.id = URL(fileURLWithPath: filePath).lastPathComponent
    self.filePath = filePath
    self.tags = tags
    self.ocrText = ocrText
    self.appName = appName
    self.date = date
    self.type = type
  }
}

/// Smart folder definitions for history filtering.
enum SmartFolder: String, CaseIterable, Identifiable {
  case all
  case today
  case thisWeek
  case screenshots
  case recordings
  case withText
  case tagged

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .all: "All"
    case .today: "Today"
    case .thisWeek: "This Week"
    case .screenshots: "Screenshots"
    case .recordings: "Recordings"
    case .withText: "With Text"
    case .tagged: "Tagged"
    }
  }

  var icon: String {
    switch self {
    case .all: "tray.full"
    case .today: "calendar"
    case .thisWeek: "calendar.badge.clock"
    case .screenshots: "photo"
    case .recordings: "video"
    case .withText: "doc.text"
    case .tagged: "tag"
    }
  }
}
