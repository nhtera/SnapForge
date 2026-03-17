import Foundation
import AppKit

/// Service for managing capture metadata — tags, OCR text, search.
/// Stores metadata as a JSON file alongside captures.
@MainActor
@Observable
final class MetadataService {
  static let shared = MetadataService()

  private(set) var metadata: [String: CaptureMetadata] = [:]  // keyed by filename
  private var metadataURL: URL {
    AppEnvironment.shared.storageService.snapForgeDirectory
      .appendingPathComponent(".metadata.json")
  }

  /// Debounce timer to batch rapid writes (e.g., during indexAllCaptures)
  private var saveTask: Task<Void, Never>?

  private init() {
    loadMetadata()
  }

  // MARK: - CRUD

  /// Get metadata for a capture filename
  func getMetadata(for filename: String) -> CaptureMetadata? {
    metadata[filename]
  }

  /// Get or create metadata for a capture
  func ensureMetadata(for capture: HistoryCapture) -> CaptureMetadata {
    if let existing = metadata[capture.filename] {
      return existing
    }
    let newMetadata = CaptureMetadata(
      filePath: capture.filePath,
      date: capture.date,
      type: capture.type.rawValue
    )
    metadata[capture.filename] = newMetadata
    saveMetadata()
    return newMetadata
  }

  /// Add a tag to a capture
  func addTag(_ tag: String, to filename: String) {
    guard var meta = metadata[filename] else { return }
    let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty, !meta.tags.contains(normalized) else { return }
    meta.tags.append(normalized)
    metadata[filename] = meta
    saveMetadata()
  }

  /// Remove a tag from a capture
  func removeTag(_ tag: String, from filename: String) {
    guard var meta = metadata[filename] else { return }
    meta.tags.removeAll { $0 == tag }
    metadata[filename] = meta
    saveMetadata()
  }

  /// Set OCR text for a capture
  func setOCRText(_ text: String, for filename: String) {
    guard var meta = metadata[filename] else { return }
    meta.ocrText = text
    metadata[filename] = meta
    saveMetadata()
  }

  /// Delete metadata for a capture
  func deleteMetadata(for filename: String) {
    metadata.removeValue(forKey: filename)
    saveMetadata()
  }

  // MARK: - Search

  /// Search captures by text (matches filename, tags, OCR text)
  func search(_ query: String, in captures: [HistoryCapture]) -> [HistoryCapture] {
    guard !query.isEmpty else { return captures }
    let lowered = query.lowercased()

    return captures.filter { capture in
      // Match filename
      if capture.filename.localizedStandardContains(query) { return true }

      // Match metadata
      if let meta = metadata[capture.filename] {
        // Match tags
        if meta.tags.contains(where: { $0.contains(lowered) }) { return true }
        // Match OCR text
        if let ocrText = meta.ocrText,
           ocrText.localizedStandardContains(query) { return true }
        // Match app name
        if let appName = meta.appName,
           appName.localizedStandardContains(query) { return true }
      }
      return false
    }
  }

  /// Filter captures by smart folder
  func filter(
    _ captures: [HistoryCapture],
    by folder: SmartFolder
  ) -> [HistoryCapture] {
    let calendar = Calendar.current
    let now = Date()

    switch folder {
    case .all:
      return captures

    case .today:
      return captures.filter { calendar.isDateInToday($0.date) }

    case .thisWeek:
      let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
      return captures.filter { $0.date >= weekAgo }

    case .screenshots:
      return captures.filter { $0.type == .screenshot }

    case .recordings:
      return captures.filter { $0.type == .recording || $0.type == .gif }

    case .withText:
      return captures.filter { capture in
        if let meta = metadata[capture.filename],
           let text = meta.ocrText, !text.isEmpty {
          return true
        }
        return false
      }

    case .tagged:
      return captures.filter { capture in
        if let meta = metadata[capture.filename], !meta.tags.isEmpty {
          return true
        }
        return false
      }
    }
  }

  /// All unique tags used across all captures
  var allTags: [String] {
    Array(Set(metadata.values.flatMap(\.tags))).sorted()
  }

  // MARK: - Auto-Indexing

  /// Index a capture by running OCR on it (async)
  func indexCapture(_ capture: HistoryCapture) async {
    var meta = ensureMetadata(for: capture)

    // Only run OCR on screenshots that haven't been indexed yet
    if capture.type == .screenshot && meta.ocrText == nil {
      if let image = NSImage(contentsOfFile: capture.filePath) {
        let text = try? await OCRService.shared.extractFullText(from: image)
        if let text, !text.isEmpty {
          meta.ocrText = text
          metadata[capture.filename] = meta
          saveMetadata()
        }
      }
    }
  }

  // MARK: - Persistence

  private func loadMetadata() {
    guard FileManager.default.fileExists(atPath: metadataURL.path),
          let data = try? Data(contentsOf: metadataURL) else { return }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    if let loaded = try? decoder.decode([String: CaptureMetadata].self, from: data) {
      metadata = loaded
    }
  }

  /// Debounced save — coalesces rapid mutations into a single disk write after 0.5s of inactivity.
  private func saveMetadata() {
    saveTask?.cancel()
    saveTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(500))
      guard !Task.isCancelled else { return }
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      guard let data = try? encoder.encode(metadata) else { return }
      try? data.write(to: metadataURL, options: .atomic)
    }
  }
}
