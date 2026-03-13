import SwiftUI

/// Capture history — scans SnapForge directory, searchable grid with type filters.
struct HistoryView: View {
    @State private var viewModel = HistoryViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Type filter chips
            filterChips
                .padding(.horizontal)
                .padding(.top, 8)

            if viewModel.filteredCaptures.isEmpty {
                ContentUnavailableView(
                    viewModel.searchText.isEmpty ? "No Captures Yet" : "No Results",
                    systemImage: viewModel.searchText.isEmpty ? "photo.stack" : "magnifyingglass",
                    description: Text(
                        viewModel.searchText.isEmpty
                            ? "Your screenshots and recordings will appear here."
                            : "No captures match \"\(viewModel.searchText)\"."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 12) {
                        ForEach(viewModel.filteredCaptures) { capture in
                            HistoryItemView(capture: capture)
                                .contextMenu {
                                    Button("Open") { viewModel.open(capture) }
                                    Button("Copy") { viewModel.copy(capture) }
                                    Button("Show in Finder") { viewModel.showInFinder(capture) }
                                    Divider()
                                    if capture.type == .screenshot {
                                        Button("Annotate") { viewModel.annotate(capture) }
                                        Button("Mockup") { viewModel.mockup(capture) }
                                        Button("OCR → Clipboard") { viewModel.ocr(capture) }
                                        Divider()
                                    }
                                    Button("Delete", role: .destructive) { viewModel.delete(capture) }
                                }
                        }
                    }
                    .padding()
                }
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Search captures...")
        .navigationTitle("Capture History")
        .onAppear { viewModel.loadCaptures() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { viewModel.loadCaptures() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: { viewModel.openInFinder() }) {
                    Image(systemName: "folder")
                }
                .help("Open in Finder")
            }
        }
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        HStack(spacing: 6) {
            FilterChip(title: "All", isSelected: viewModel.typeFilter == nil) {
                viewModel.typeFilter = nil
            }
            FilterChip(title: "Screenshots", isSelected: viewModel.typeFilter == .screenshot) {
                viewModel.typeFilter = .screenshot
            }
            FilterChip(title: "Recordings", isSelected: viewModel.typeFilter == .recording) {
                viewModel.typeFilter = .recording
            }
            FilterChip(title: "GIFs", isSelected: viewModel.typeFilter == .gif) {
                viewModel.typeFilter = .gif
            }
            Spacer()
            Text("\(viewModel.filteredCaptures.count) items")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear, in: Capsule())
                .foregroundColor(isSelected ? .accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - History Item

struct HistoryItemView: View {
    let capture: HistoryCapture

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Thumbnail
            if let image = NSImage(contentsOfFile: capture.filePath) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topTrailing) {
                        typeIcon
                    }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(height: 100)
                    .overlay {
                        Image(systemName: capture.type.icon)
                            .foregroundStyle(.secondary)
                    }
                    .overlay(alignment: .topTrailing) {
                        typeIcon
                    }
            }

            // Filename
            Text(capture.filename)
                .font(.caption)
                .lineLimit(1)

            // Date + size
            HStack {
                Text(capture.date.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(capture.formattedSize)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var typeIcon: some View {
        Image(systemName: capture.type.icon)
            .font(.system(size: 9))
            .foregroundColor(.white)
            .padding(4)
            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
            .padding(4)
    }
}

// MARK: - View Model

@MainActor
@Observable
final class HistoryViewModel {
    var captures: [HistoryCapture] = []
    var searchText = ""
    var typeFilter: HistoryCapture.CaptureType?

    var filteredCaptures: [HistoryCapture] {
        captures.filter { capture in
            // Type filter
            if let typeFilter, capture.type != typeFilter { return false }
            // Text search
            if !searchText.isEmpty {
                return capture.filename.localizedCaseInsensitiveContains(searchText)
            }
            return true
        }
    }

    func loadCaptures() {
        let storage = AppEnvironment.shared.storageService
        let directory = storage.snapForgeDirectory
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
    }

    func open(_ capture: HistoryCapture) {
        NSWorkspace.shared.open(URL(fileURLWithPath: capture.filePath))
    }

    func copy(_ capture: HistoryCapture) {
        if let image = NSImage(contentsOfFile: capture.filePath) {
            ClipboardService().copyImage(image)
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
            if let text = try? await OCRService.shared.extractFullText(from: image), !text.isEmpty {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
    }

    func delete(_ capture: HistoryCapture) {
        try? FileManager.default.removeItem(atPath: capture.filePath)
        captures.removeAll { $0.id == capture.id }
    }

    func openInFinder() {
        let storage = AppEnvironment.shared.storageService
        NSWorkspace.shared.open(storage.snapForgeDirectory)
    }
}

/// Model for a history entry.
struct HistoryCapture: Identifiable {
    let id = UUID()
    let filename: String
    let filePath: String
    let date: Date
    let fileSize: Int64
    let type: CaptureType

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    enum CaptureType: String {
        case screenshot, recording, gif

        var icon: String {
            switch self {
            case .screenshot: "photo"
            case .recording: "video"
            case .gif: "photo.stack"
            }
        }
    }
}
