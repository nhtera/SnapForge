import SwiftUI

/// Sticker library panel — searchable grid of built-in stickers organized by category.
/// Click a sticker to place it at the center of the canvas.
struct StickerLibraryView: View {
  @ObservedObject var state: AnnotateState
  @State private var searchText = ""
  @State private var selectedCategory: StickerCategory?

  private var filteredStickers: [StickerItem] {
    let stickers: [StickerItem]
    if let category = selectedCategory {
      stickers = StickerItem.builtIn.filter { $0.category == category }
    } else {
      stickers = StickerItem.builtIn
    }

    if searchText.isEmpty {
      return stickers
    }
    return stickers.filter {
      $0.name.localizedStandardContains(searchText)
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        Text("Stickers")
          .font(.system(size: 13, weight: .semibold))
        Spacer()
        Button(action: { state.isStickerLibraryVisible = false }) {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)

      Divider()

      // Category tabs — single row, scrollable with any mouse
      HorizontalMouseScrollView {
        HStack(spacing: 6) {
          categoryChip(title: "All", category: nil)
          ForEach(StickerCategory.allCases) { category in
            categoryChip(title: category.displayName, category: category)
          }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
      }

      Divider()

      // Search
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
          .font(.system(size: 11))
        TextField("Search stickers…", text: $searchText)
          .textFieldStyle(.plain)
          .font(.system(size: 12))
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(Color(white: 0.15))

      // Sticker grid
      ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 48))], spacing: 8) {
          ForEach(filteredStickers) { sticker in
            stickerButton(sticker)
          }
        }
        .padding(12)
      }
    }
    .frame(width: 240)
    .background(Color(nsColor: .controlBackgroundColor))
  }

  // MARK: - Components

  private func categoryChip(title: String, category: StickerCategory?) -> some View {
    Button(action: { selectedCategory = category }) {
      Text(title)
        .font(.system(size: 10, weight: selectedCategory == category ? .semibold : .regular))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
          selectedCategory == category
            ? Color.accentColor.opacity(0.15)
            : Color.clear,
          in: Capsule()
        )
        .foregroundStyle(selectedCategory == category ? Color.accentColor : .secondary)
    }
    .buttonStyle(.plain)
  }

  private func stickerButton(_ sticker: StickerItem) -> some View {
    Button(action: { placeSticker(sticker) }) {
      VStack(spacing: 4) {
        Image(systemName: sticker.symbol)
          .font(.system(size: 24))
          .frame(width: 44, height: 44)
          .background(Color(white: 0.2), in: RoundedRectangle(cornerRadius: 8))

        Text(sticker.name)
          .font(.system(size: 9))
          .lineLimit(1)
          .foregroundStyle(.secondary)
      }
    }
    .buttonStyle(.plain)
  }

  // MARK: - Actions

  private func placeSticker(_ sticker: StickerItem) {
    state.placeSticker(sticker)
  }
}
