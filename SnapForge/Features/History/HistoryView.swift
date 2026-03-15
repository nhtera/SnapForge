import SwiftUI

/// Capture history — smart folders, tags, OCR-powered search, grid with filters.
struct HistoryView: View {
    @State private var viewModel = HistoryViewModel()
    @State private var showBatchExport = false
    // Drag selection state
    @State private var dragSelectionRect: CGRect?
    @State private var dragStart: CGPoint?
    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var preDragSelection: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            // Smart folder bar
            smartFolderBar
                .padding(.horizontal)
                .padding(.top, 8)

            // Tag filter chips (if any tags exist)
            if !viewModel.availableTags.isEmpty {
                tagFilterBar
                    .padding(.horizontal)
                    .padding(.top, 4)
            }

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
                ZStack(alignment: .bottom) {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 16) {
                            ForEach(viewModel.filteredCaptures) { capture in
                                HistoryItemView(
                                    capture: capture,
                                    viewModel: viewModel,
                                    isMultiSelectMode: viewModel.isMultiSelectMode,
                                    isSelected: viewModel.selectedCaptureIds.contains(capture.id)
                                )
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: ItemFramePreferenceKey.self,
                                            value: [capture.id: geo.frame(in: .named("historyGrid"))]
                                        )
                                    }
                                )
                                .onTapGesture {
                                    if viewModel.isMultiSelectMode {
                                        viewModel.toggleSelection(capture)
                                    }
                                }
                                .contextMenu {
                                    Button("Open") { viewModel.open(capture) }
                                    Button("Copy") { viewModel.copy(capture) }
                                    Button("Show in Finder") { viewModel.showInFinder(capture) }
                                    Divider()
                                    if capture.type == .screenshot {
                                        Button("Annotate") { viewModel.annotate(capture) }
                                        Button("Mockup") { viewModel.mockup(capture) }
                                        Button("OCR → Clipboard") { viewModel.ocr(capture) }
                                        Button("Index (OCR)") { viewModel.indexCapture(capture) }
                                        Divider()
                                    }
                                    // Tag submenu
                                    Menu("Tags") {
                                        ForEach(viewModel.suggestedTags, id: \.self) { tag in
                                            let hasTag = viewModel.captureHasTag(capture, tag: tag)
                                            Button(action: {
                                                if hasTag {
                                                    viewModel.removeTag(tag, from: capture)
                                                } else {
                                                    viewModel.addTag(tag, to: capture)
                                                }
                                            }) {
                                                HStack {
                                                    Text(tag)
                                                    if hasTag {
                                                        Image(systemName: "checkmark")
                                                    }
                                                }
                                            }
                                        }
                                        Divider()
                                        Button("Add New Tag…") { viewModel.promptNewTag(for: capture) }
                                    }
                                    Divider()
                                    Button("Delete", role: .destructive) { viewModel.delete(capture) }
                                }
                            }
                        }
                        .padding(16)
                        .padding(.bottom, viewModel.isMultiSelectMode ? 70 : 0)
                    }
                    .coordinateSpace(name: "historyGrid")
                    .onPreferenceChange(ItemFramePreferenceKey.self) { frames in
                        itemFrames.merge(frames) { _, new in new }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 15, coordinateSpace: .named("historyGrid"))
                            .onChanged { value in
                                // Auto-enter multi-select mode on drag
                                if !viewModel.isMultiSelectMode {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        viewModel.isMultiSelectMode = true
                                    }
                                }

                                if dragStart == nil {
                                    dragStart = value.startLocation
                                    // Preserve existing selection
                                    preDragSelection = viewModel.selectedCaptureIds
                                }

                                let origin = CGPoint(
                                    x: min(value.startLocation.x, value.location.x),
                                    y: min(value.startLocation.y, value.location.y)
                                )
                                let size = CGSize(
                                    width: abs(value.location.x - value.startLocation.x),
                                    height: abs(value.location.y - value.startLocation.y)
                                )
                                let selRect = CGRect(origin: origin, size: size)
                                dragSelectionRect = selRect

                                updateDragSelection(rect: selRect)
                            }
                            .onEnded { _ in
                                withAnimation(.easeOut(duration: 0.2)) {
                                    dragSelectionRect = nil
                                }
                                dragStart = nil
                            }
                    )
                    .overlay {
                        dragSelectionOverlay
                    }

                    // Multi-select floating action bar
                    if viewModel.isMultiSelectMode && !viewModel.selectedCaptureIds.isEmpty {
                        multiSelectActionBar
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Search captures, tags, text…")
        .navigationTitle("Capture History")
        .task { viewModel.loadCaptures() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.isMultiSelectMode.toggle()
                        if !viewModel.isMultiSelectMode {
                            viewModel.selectedCaptureIds.removeAll()
                        }
                    }
                }) {
                    Image(systemName: viewModel.isMultiSelectMode ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .help(viewModel.isMultiSelectMode ? "Exit Multi-Select" : "Multi-Select")
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: { viewModel.indexAllCaptures() }) {
                    Image(systemName: "text.viewfinder")
                }
                .help("Index All (OCR)")
            }
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
        .sheet(isPresented: $viewModel.showingTagInput) {
            TagInputSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showBatchExport) {
            BatchExportView(captures: viewModel.selectedItems)
        }
    }

    // MARK: - Drag Selection Overlay

    @ViewBuilder
    private var dragSelectionOverlay: some View {
        // The rubber-band selection rectangle (visual only, doesn't block clicks)
        GeometryReader { _ in
            if let rect = dragSelectionRect {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.12))
                    .overlay {
                        Rectangle()
                            .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1)
                    }
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false)
    }

    private func updateDragSelection(rect: CGRect) {
        var newSelection = preDragSelection
        for capture in viewModel.filteredCaptures {
            if let frame = itemFrames[capture.id], frame.intersects(rect) {
                newSelection.insert(capture.id)
            }
        }
        viewModel.selectedCaptureIds = newSelection
    }

    // MARK: - Multi-Select Action Bar

    private var multiSelectActionBar: some View {
        HStack(spacing: 12) {
            Text("\(viewModel.selectedCaptureIds.count) selected")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Divider().frame(height: 20)

            let selectedScreenshots = viewModel.selectedScreenshots

            if selectedScreenshots.count >= 2 {
                Button(action: { viewModel.stitchSelected() }) {
                    Label("Stitch", systemImage: "rectangle.split.3x1")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
            }

            if selectedScreenshots.count == 2 {
                Button(action: { viewModel.compareSelected() }) {
                    Label("Compare", systemImage: "square.split.2x1")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
            }

            Button(action: { showBatchExport = true }) {
                Label("Export", systemImage: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)

            Button(action: {
                viewModel.deleteSelected()
            }) {
                Label("Delete", systemImage: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)

            Divider().frame(height: 20)

            Button("Select All") {
                viewModel.selectAll()
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
        .padding(.bottom, 12)
    }

    // MARK: - Smart Folder Bar

    private var smartFolderBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SmartFolder.allCases) { folder in
                    FilterChip(
                        title: folder.displayName,
                        icon: folder.icon,
                        isSelected: viewModel.selectedFolder == folder
                    ) {
                        viewModel.selectedFolder = folder
                    }
                }
                Spacer()
                Text("\(viewModel.filteredCaptures.count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Tag Filter Bar

    private var tagFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Image(systemName: "tag")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                ForEach(viewModel.availableTags, id: \.self) { tag in
                    TagChip(
                        tag: tag,
                        isSelected: viewModel.selectedTag == tag
                    ) {
                        viewModel.selectedTag = viewModel.selectedTag == tag ? nil : tag
                    }
                }
            }
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 9))
                }
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear, in: Capsule())
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tag Chip

struct TagChip: View {
    let tag: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("#\(tag)")
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(
                    isSelected ? Color.accentColor.opacity(0.2) : Color(white: 0.2),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tag Input Sheet

struct TagInputSheet: View {
    @ObservedObject var viewModel: HistoryViewModel
    @State private var tagText = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Tag")
                .font(.headline)

            TextField("Enter tag name…", text: $tagText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submit() }

            HStack {
                Button("Cancel") { viewModel.showingTagInput = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(tagText.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
    }

    private func submit() {
        guard !tagText.isEmpty else { return }
        if let capture = viewModel.tagInputCapture {
            viewModel.addTag(tagText, to: capture)
        }
        viewModel.showingTagInput = false
    }
}

// MARK: - History Item Card

struct HistoryItemView: View {
    let capture: HistoryCapture
    @ObservedObject var viewModel: HistoryViewModel
    var isMultiSelectMode: Bool = false
    var isSelected: Bool = false
    @State private var isHovered = false

    private var tags: [String] {
        MetadataService.shared.getMetadata(for: capture.filename)?.tags ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail — fixed height, clipped to prevent tall images overflowing
            thumbnailView
                .frame(maxWidth: .infinity)
                .frame(height: 140)
                .clipped()
                .contentShape(Rectangle())
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    typeBadge.padding(6)
                }
                .overlay(alignment: .topLeading) {
                    if isMultiSelectMode {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(isSelected ? Color.accentColor : .white.opacity(0.7))
                            .shadow(color: .black.opacity(0.4), radius: 2)
                            .padding(6)
                            .transition(.scale.combined(with: .opacity))
                    }
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

                // Tags row
                if !tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 3) {
                            ForEach(tags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(.cyan)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.cyan.opacity(0.1), in: Capsule())
                            }
                        }
                    }
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
                    isSelected ? Color.accentColor : (isHovered ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.06)),
                    lineWidth: isSelected ? 2 : 1
                )
        }
        .shadow(color: .black.opacity(isHovered ? 0.25 : 0.1), radius: isHovered ? 8 : 4, y: 2)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in isHovered = hovering }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        GeometryReader { geo in
            if let image = NSImage(contentsOfFile: capture.filePath) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
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
final class HistoryViewModel: ObservableObject {
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

// MARK: - Item Frame Preference Key

/// Collects each grid item's frame for drag-selection intersection testing.
struct ItemFramePreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
