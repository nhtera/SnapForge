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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 16) {
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
                    .padding(16)
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
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - History Item Card

struct HistoryItemView: View {
    let capture: HistoryCapture
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail — fixed height, properly contained
            thumbnailView
                .frame(height: 130)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    typeBadge
                        .padding(6)
                }

            // Info section
            VStack(alignment: .leading, spacing: 4) {
                Text(capture.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 0) {
                    Text(capture.date.formatted(.relative(presentation: .named)))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(capture.formattedSize)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Color(white: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isHovered ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.06),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(isHovered ? 0.25 : 0.1), radius: isHovered ? 8 : 4, y: 2)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in isHovered = hovering }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let image = NSImage(contentsOfFile: capture.filePath) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle()
                .fill(Color(white: 0.15))
                .overlay {
                    Image(systemName: capture.type.icon)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var typeBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: capture.type.icon)
                .font(.system(size: 8, weight: .semibold))
            Text(capture.type.label)
                .font(.system(size: 8, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.black.opacity(0.6), in: Capsule())
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
            if let typeFilter, capture.type != typeFilter { return false }
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

    /// Shortened display name: remove "SnapForge_" prefix
    var displayName: String {
        var name = filename
        if name.hasPrefix("SnapForge_") {
            name = String(name.dropFirst("SnapForge_".count))
        }
        if name.hasPrefix("Recording_") {
            name = String(name.dropFirst("Recording_".count))
        }
        return name
    }

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

        var label: String {
            switch self {
            case .screenshot: "IMG"
            case .recording: "MOV"
            case .gif: "GIF"
            }
        }
    }
}
