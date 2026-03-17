import SwiftUI
import AppKit

/// View model for the capture history view.
@MainActor
@Observable
final class HistoryViewModel {
    var captures: [HistoryCapture] = []
    var searchText = ""
    var selectedFolder: SmartFolder = .all
    var selectedTag: String?
    var showingTagInput = false
    var tagInputCapture: HistoryCapture?

    // Multi-select state
    var isMultiSelectMode = false
    var selectedCaptureIds: Set<UUID> = []

    var filteredCaptures: [HistoryCapture] {
        var result = captures

        // Apply smart folder filter
        result = MetadataService.shared.filter(result, by: selectedFolder)

        // Apply tag filter
        if let tag = selectedTag {
            result = result.filter { capture in
                MetadataService.shared.getMetadata(for: capture.filename)?.tags.contains(tag) ?? false
            }
        }

        // Apply search
        if !searchText.isEmpty {
            result = MetadataService.shared.search(searchText, in: result)
        }

        return result
    }

    var availableTags: [String] {
        MetadataService.shared.allTags
    }

    var suggestedTags: [String] {
        let common = ["important", "bug", "design", "review", "reference", "todo", "docs"]
        return Array(Set(common + availableTags)).sorted()
    }

    func loadCaptures() {
        let storage = AppEnvironment.shared.storageService
        let directory = storage.snapForgeDirectory
        let access = SandboxFileAccessManager.shared.beginAccessingURL(directory)
        defer { access.stop() }
        let fm = FileManager.default

        guard let urls = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            captures = []
            return
        }

        let supportedExtensions = Set(["png", "jpg", "jpeg", "gif", "mov", "mp4", "webp", "heic"])

        captures = urls.compactMap { url -> HistoryCapture? in
            let ext = url.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { return nil }

            let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let date = resourceValues?.contentModificationDate ?? Date.distantPast
            let size = resourceValues?.fileSize ?? 0

            let type: HistoryCapture.CaptureType
            switch ext {
            case "gif": type = .gif
            case "mov", "mp4": type = .recording
            default: type = .screenshot
            }

            return HistoryCapture(
                filename: url.lastPathComponent,
                filePath: url.path,
                date: date,
                fileSize: Int64(size),
                type: type
            )
        }
        .sorted { $0.date > $1.date }

        // Ensure metadata exists for all captures
        for capture in captures {
            _ = MetadataService.shared.ensureMetadata(for: capture)
        }
    }

    // MARK: - Actions

    func open(_ capture: HistoryCapture) {
        NSWorkspace.shared.open(URL(fileURLWithPath: capture.filePath))
    }

    func copy(_ capture: HistoryCapture) {
        if let image = NSImage(contentsOfFile: capture.filePath) {
            AppEnvironment.shared.clipboardService.copyImage(image)
        }
    }

    func showInFinder(_ capture: HistoryCapture) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: capture.filePath)])
    }

    func annotate(_ capture: HistoryCapture) {
        if let image = NSImage(contentsOfFile: capture.filePath) {
            AppCoordinator.shared.showAnnotationEditor(for: image)
        }
    }

    func mockup(_ capture: HistoryCapture) {
        if let image = NSImage(contentsOfFile: capture.filePath) {
            AppCoordinator.shared.showBackgroundMockup(for: image)
        }
    }

    func ocr(_ capture: HistoryCapture) {
        guard let image = NSImage(contentsOfFile: capture.filePath) else { return }
        Task {
            do {
                let text = try await OCRService.shared.extractFullText(from: image)
                guard !text.isEmpty else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } catch is CancellationError {
                // Normal lifecycle — do nothing
            } catch {
                print("❌ OCR failed: \(error.localizedDescription)")
            }
        }
    }

    func delete(_ capture: HistoryCapture) {
        let url = URL(fileURLWithPath: capture.filePath)
        let access = SandboxFileAccessManager.shared.beginAccessingURL(url)
        defer { access.stop() }
        try? FileManager.default.removeItem(at: url)
        MetadataService.shared.deleteMetadata(for: capture.filename)
        captures.removeAll { $0.id == capture.id }
    }

    func openInFinder() {
        let storage = AppEnvironment.shared.storageService
        NSWorkspace.shared.open(storage.snapForgeDirectory)
    }

    // MARK: - Tag Management

    func addTag(_ tag: String, to capture: HistoryCapture) {
        MetadataService.shared.addTag(tag, to: capture.filename)
    }

    func removeTag(_ tag: String, from capture: HistoryCapture) {
        MetadataService.shared.removeTag(tag, from: capture.filename)
    }

    func captureHasTag(_ capture: HistoryCapture, tag: String) -> Bool {
        MetadataService.shared.getMetadata(for: capture.filename)?.tags.contains(tag) ?? false
    }

    func promptNewTag(for capture: HistoryCapture) {
        tagInputCapture = capture
        showingTagInput = true
    }

    // MARK: - Indexing

    func indexCapture(_ capture: HistoryCapture) {
        Task {
            await MetadataService.shared.indexCapture(capture)
        }
    }

    func indexAllCaptures() {
        let screenshots = captures.filter { $0.type == .screenshot }
        Task {
            for capture in screenshots {
                await MetadataService.shared.indexCapture(capture)
            }
        }
    }

    // MARK: - Multi-Select

    func toggleSelection(_ capture: HistoryCapture) {
        if selectedCaptureIds.contains(capture.id) {
            selectedCaptureIds.remove(capture.id)
        } else {
            selectedCaptureIds.insert(capture.id)
        }
    }

    func selectAll() {
        selectedCaptureIds = Set(filteredCaptures.map(\.id))
    }

    /// Screenshots currently selected (for stitch/compare)
    var selectedScreenshots: [HistoryCapture] {
        filteredCaptures.filter { capture in
            selectedCaptureIds.contains(capture.id) && capture.type == .screenshot
        }
    }

    /// All selected captures (for export/delete)
    var selectedItems: [HistoryCapture] {
        filteredCaptures.filter { selectedCaptureIds.contains($0.id) }
    }

    func stitchSelected() {
        let images = selectedScreenshots.compactMap { NSImage(contentsOfFile: $0.filePath) }
        guard images.count >= 2 else { return }
        AppCoordinator.shared.showStitcher(images: images)
    }

    func compareSelected() {
        let screenshots = selectedScreenshots
        guard screenshots.count == 2 else { return }
        let imageA = NSImage(contentsOfFile: screenshots[0].filePath)
        let imageB = NSImage(contentsOfFile: screenshots[1].filePath)
        AppCoordinator.shared.showScreenDiff(imageA: imageA, imageB: imageB)
    }

    func deleteSelected() {
        for capture in selectedItems {
            try? FileManager.default.removeItem(atPath: capture.filePath)
            MetadataService.shared.deleteMetadata(for: capture.filename)
        }
        captures.removeAll { selectedCaptureIds.contains($0.id) }
        selectedCaptureIds.removeAll()
    }
}
