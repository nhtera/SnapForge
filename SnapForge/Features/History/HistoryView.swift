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
        ZStack {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
        .padding(.bottom, 12)
    }

    // MARK: - Smart Folder Bar

    private var smartFolderBar: some View {
        ScrollView(.horizontal) {
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
        .scrollIndicators(.hidden)
    }

    // MARK: - Tag Filter Bar

    private var tagFilterBar: some View {
        ScrollView(.horizontal) {
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
        .scrollIndicators(.hidden)
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
