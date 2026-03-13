import Foundation

/// Represents a .snapforge project file (JSON + images bundle).
struct SnapForgeProject: Codable, Identifiable {
    let id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    var baseImagePath: String
    var annotations: [CodableAnnotation]
    var exportSettings: ProjectExportSettings

    init(name: String, baseImagePath: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.baseImagePath = baseImagePath
        self.annotations = []
        self.exportSettings = ProjectExportSettings()
    }
}

/// Codable wrapper for annotation data (simplified for serialization).
struct CodableAnnotation: Codable, Identifiable {
    let id: UUID
    let type: String
    let data: Data // JSON-encoded annotation-specific data
}

/// Export settings stored in a project file.
struct ProjectExportSettings: Codable {
    var format: String = "png"
    var quality: Double = 0.9
    var scale: Double = 2.0 // Retina
}
