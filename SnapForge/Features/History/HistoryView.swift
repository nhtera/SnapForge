import SwiftUI

/// Capture history — 30-day grid of captured images.
struct HistoryView: View {
    @State private var viewModel = HistoryViewModel()

    var body: some View {
        NavigationStack {
            VStack {
                if viewModel.captures.isEmpty {
                    ContentUnavailableView(
                        "No Captures Yet",
                        systemImage: "photo.stack",
                        description: Text("Your screenshots and recordings will appear here.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 12) {
                            ForEach(viewModel.captures) { capture in
                                HistoryItemView(capture: capture)
                                    .contextMenu {
                                        Button("Open") { viewModel.open(capture) }
                                        Button("Copy") { viewModel.copy(capture) }
                                        Divider()
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
        }
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
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(height: 100)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }

            // Metadata
            Text(capture.filename)
                .font(.caption)
                .lineLimit(1)

            Text(capture.date.formatted(.relative(presentation: .named)))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - View Model

@Observable
final class HistoryViewModel {
    var captures: [HistoryCapture] = []
    var searchText = ""

    func open(_ capture: HistoryCapture) {
        NSWorkspace.shared.open(URL(fileURLWithPath: capture.filePath))
    }

    func copy(_ capture: HistoryCapture) {
        if let image = NSImage(contentsOfFile: capture.filePath) {
            ClipboardService().copyImage(image)
        }
    }

    func delete(_ capture: HistoryCapture) {
        try? FileManager.default.removeItem(atPath: capture.filePath)
        captures.removeAll { $0.id == capture.id }
    }
}

/// Model for a history entry.
struct HistoryCapture: Identifiable {
    let id = UUID()
    let filename: String
    let filePath: String
    let date: Date
    let type: CaptureType

    enum CaptureType: String {
        case screenshot, recording, gif
    }
}
