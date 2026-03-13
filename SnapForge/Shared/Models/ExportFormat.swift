import Foundation

/// Export format model used across the app.
struct ExportFormat: Identifiable, Hashable {
    let id: String
    let name: String
    let fileExtension: String

    static let png = ExportFormat(id: "png", name: "PNG", fileExtension: "png")
    static let jpg = ExportFormat(id: "jpg", name: "JPG", fileExtension: "jpg")
    static let webp = ExportFormat(id: "webp", name: "WebP", fileExtension: "webp")
    static let heic = ExportFormat(id: "heic", name: "HEIC", fileExtension: "heic")
    static let mp4 = ExportFormat(id: "mp4", name: "MP4", fileExtension: "mp4")
    static let gif = ExportFormat(id: "gif", name: "GIF", fileExtension: "gif")

    static let imageFormats: [ExportFormat] = [.png, .jpg, .webp, .heic]
    static let videoFormats: [ExportFormat] = [.mp4, .gif]
}
