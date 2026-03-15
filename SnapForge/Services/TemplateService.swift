import Foundation
import SwiftUI

/// Service for saving, loading, and managing annotation templates.
@MainActor @Observable
final class TemplateService {
  static let shared = TemplateService()

  var templates: [AnnotationTemplate] = []

  private let fileManager = FileManager.default
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  private var templatesDirectory: URL {
    guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      // Fallback to temporary directory if app support is unavailable
      return fileManager.temporaryDirectory.appendingPathComponent("SnapForge/Templates", isDirectory: true)
    }
    return appSupport.appendingPathComponent("SnapForge/Templates", isDirectory: true)
  }

  init() {
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    ensureDirectoryExists()
    loadAll()
    insertBuiltInTemplates()
  }

  // MARK: - Directory

  private func ensureDirectoryExists() {
    try? fileManager.createDirectory(at: templatesDirectory, withIntermediateDirectories: true)
  }

  // MARK: - Save

  func save(annotations: [AnnotationItem], name: String, description: String = "") throws {
    let items = annotations.map { SerializableAnnotation(from: $0) }
    let template = AnnotationTemplate(
      name: name,
      description: description,
      items: items
    )

    let fileURL = templatesDirectory.appendingPathComponent("\(template.id.uuidString).json")
    let data = try encoder.encode(template)
    try data.write(to: fileURL)

    templates.append(template)
    print("✅ Template saved: \(name) (\(items.count) annotations)")
  }

  // MARK: - Load

  func loadAll() {
    templates.removeAll()

    guard let files = try? fileManager.contentsOfDirectory(
      at: templatesDirectory,
      includingPropertiesForKeys: nil
    ) else { return }

    for file in files where file.pathExtension == "json" {
      guard let data = try? Data(contentsOf: file),
            let template = try? decoder.decode(AnnotationTemplate.self, from: data)
      else { continue }
      templates.append(template)
    }

    templates.sort { $0.createdAt > $1.createdAt }
    print("✅ Loaded \(templates.count) templates")
  }

  // MARK: - Delete

  func delete(id: UUID) throws {
    let fileURL = templatesDirectory.appendingPathComponent("\(id.uuidString).json")
    if fileManager.fileExists(atPath: fileURL.path) {
      try fileManager.removeItem(at: fileURL)
    }
    templates.removeAll { $0.id == id }
  }

  // MARK: - Apply

  /// Convert template items back to AnnotationItems, offset to avoid overlapping existing annotations.
  func applyTemplate(_ template: AnnotationTemplate, offset: CGPoint = CGPoint(x: 20, y: 20)) -> [AnnotationItem] {
    template.items.compactMap { serialized in
      guard var item = serialized.toAnnotationItem() else { return nil as AnnotationItem? }
      // Offset to not overlap existing
      item.bounds = item.bounds.offsetBy(dx: offset.x, dy: offset.y)
      return item
    }
  }

  // MARK: - Built-in Templates

  private func insertBuiltInTemplates() {
    let existingNames = Set(templates.map(\.name))

    if !existingNames.contains("Bug Report") {
      let bugReport = AnnotationTemplate(
        name: "Bug Report",
        description: "Numbered steps with blur for sensitive data",
        items: [
          SerializableAnnotation(from: AnnotationItem(
            type: .counter(1),
            bounds: CGRect(x: 30, y: 30, width: 24, height: 24),
            properties: AnnotationProperties(strokeColor: .red)
          )),
          SerializableAnnotation(from: AnnotationItem(
            type: .counter(2),
            bounds: CGRect(x: 30, y: 100, width: 24, height: 24),
            properties: AnnotationProperties(strokeColor: .red)
          )),
          SerializableAnnotation(from: AnnotationItem(
            type: .counter(3),
            bounds: CGRect(x: 30, y: 170, width: 24, height: 24),
            properties: AnnotationProperties(strokeColor: .red)
          )),
          SerializableAnnotation(from: AnnotationItem(
            type: .blur(.pixelated),
            bounds: CGRect(x: 200, y: 300, width: 200, height: 60),
            properties: AnnotationProperties()
          )),
        ],
        isBuiltIn: true
      )
      templates.insert(bugReport, at: 0)
    }

    if !existingNames.contains("Tutorial Steps") {
      let tutorial = AnnotationTemplate(
        name: "Tutorial Steps",
        description: "Arrows and counters for step-by-step guides",
        items: [
          SerializableAnnotation(from: AnnotationItem(
            type: .counter(1),
            bounds: CGRect(x: 40, y: 40, width: 24, height: 24),
            properties: AnnotationProperties(strokeColor: .orange)
          )),
          SerializableAnnotation(from: AnnotationItem(
            type: .arrow(start: CGPoint(x: 70, y: 52), end: CGPoint(x: 170, y: 52)),
            bounds: CGRect(x: 70, y: 42, width: 100, height: 20),
            properties: AnnotationProperties(strokeColor: .orange, strokeWidth: 3)
          )),
          SerializableAnnotation(from: AnnotationItem(
            type: .counter(2),
            bounds: CGRect(x: 180, y: 40, width: 24, height: 24),
            properties: AnnotationProperties(strokeColor: .orange)
          )),
          SerializableAnnotation(from: AnnotationItem(
            type: .arrow(start: CGPoint(x: 210, y: 52), end: CGPoint(x: 310, y: 52)),
            bounds: CGRect(x: 210, y: 42, width: 100, height: 20),
            properties: AnnotationProperties(strokeColor: .orange, strokeWidth: 3)
          )),
          SerializableAnnotation(from: AnnotationItem(
            type: .counter(3),
            bounds: CGRect(x: 320, y: 40, width: 24, height: 24),
            properties: AnnotationProperties(strokeColor: .orange)
          )),
        ],
        isBuiltIn: true
      )
      templates.insert(tutorial, at: 1)
    }

    if !existingNames.contains("Social Callout") {
      let social = AnnotationTemplate(
        name: "Social Callout",
        description: "Text callout with highlight background",
        items: [
          SerializableAnnotation(from: AnnotationItem(
            type: .filledRectangle,
            bounds: CGRect(x: 50, y: 50, width: 300, height: 60),
            properties: AnnotationProperties(strokeColor: .yellow, fillColor: .yellow.opacity(0.3), strokeWidth: 2)
          )),
          SerializableAnnotation(from: AnnotationItem(
            type: .text("Your text here"),
            bounds: CGRect(x: 60, y: 60, width: 280, height: 40),
            properties: AnnotationProperties(strokeColor: .white, fontSize: 20)
          )),
          SerializableAnnotation(from: AnnotationItem(
            type: .arrow(start: CGPoint(x: 200, y: 110), end: CGPoint(x: 200, y: 200)),
            bounds: CGRect(x: 190, y: 110, width: 20, height: 90),
            properties: AnnotationProperties(strokeColor: .yellow, strokeWidth: 3)
          )),
        ],
        isBuiltIn: true
      )
      templates.insert(social, at: 2)
    }
  }
}
