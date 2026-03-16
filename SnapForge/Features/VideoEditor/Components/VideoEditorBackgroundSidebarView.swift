import AppKit
import SwiftUI

/// Right sidebar for video background customization.
/// Provides gradient, wallpaper, solid color, and slider controls for padding/shadow/corners.
struct VideoEditorBackgroundSidebarView: View {
    @Bindable var state: VideoEditorState

    @State private var wallpaperManager = SystemWallpaperManager.shared
    @State private var customWallpapers: [URL] = []

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                noneButton
                gradientSection
                wallpaperSection
                colorSection

                Divider()

                slidersSection

                Spacer(minLength: DesignTokens.Spacing.lg)
            }
            .padding(DesignTokens.Spacing.md)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - None Button

    private var noneButton: some View {
        Button {
            state.snapshotBackgroundState()
            state.backgroundStyle = .none
            state.backgroundPadding = 0
            state.backgroundShadowIntensity = 0
            state.backgroundCornerRadius = 0
            state.commitBackgroundChange()
        } label: {
            Text("None")
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .fill(
                            state.backgroundStyle == .none
                                ? Color.accentColor.opacity(0.3)
                                : Color.white.opacity(0.1)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .stroke(
                            state.backgroundStyle == .none ? Color.accentColor : Color.clear,
                            lineWidth: 1.5
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Gradient Section

    private var gradientSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            VideoEditorSectionHeader(title: "Gradients")

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 8),
                    count: 6
                ),
                spacing: 8
            ) {
                ForEach(VideoGradientPreset.allCases) { preset in
                    VideoEditorGradientPresetButton(
                        preset: preset,
                        isSelected: state.backgroundStyle == .gradient(preset)
                    ) {
                        state.snapshotBackgroundState()
                        if state.backgroundPadding <= 0 {
                            state.backgroundPadding = 24
                        }
                        state.backgroundStyle = .gradient(preset)
                        state.commitBackgroundChange()
                    }
                }
            }
        }
    }

    // MARK: - Wallpaper Section

    private var wallpaperSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            VideoEditorSectionHeader(title: "Wallpapers")

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 8),
                    count: 6
                ),
                spacing: 8
            ) {
                // System wallpapers
                ForEach(wallpaperManager.wallpapers) { item in
                    WallpaperThumbnailButton(
                        item: item,
                        isSelected: isWallpaperSelected(item.fullImageURL)
                    ) {
                        selectWallpaper(item.fullImageURL)
                    }
                }

                // Custom wallpapers
                ForEach(customWallpapers, id: \.self) { url in
                    WallpaperThumbnailButton(
                        item: SystemWallpaperManager.WallpaperItem(
                            fullImageURL: url,
                            thumbnailURL: nil,
                            name: url.lastPathComponent
                        ),
                        isSelected: isWallpaperSelected(url)
                    ) {
                        selectWallpaper(url)
                    }
                }

                // Add custom wallpaper button
                addWallpaperButton
            }

            if wallpaperManager.isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Loading…")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            await wallpaperManager.loadWallpapers()
        }
    }

    // MARK: - Wallpaper Helpers

    private func isWallpaperSelected(_ url: URL) -> Bool {
        if case .wallpaper(let selectedURL) = state.backgroundStyle {
            return selectedURL == url
        }
        return false
    }

    private func selectWallpaper(_ url: URL) {
        state.snapshotBackgroundState()
        if state.backgroundPadding <= 0 {
            state.backgroundPadding = 24
        }
        state.backgroundStyle = .wallpaper(url)
        state.commitBackgroundChange()
    }

    private var addWallpaperButton: some View {
        Button {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            if panel.runModal() == .OK, let url = panel.url {
                customWallpapers.append(url)
                selectWallpaper(url)
            }
        } label: {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(Color.white.opacity(0.06))
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Color Section

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            VideoEditorSectionHeader(title: "Colors")

            VideoEditorColorSwatchGrid(selectedColor: colorBinding)
        }
    }

    private var colorBinding: Binding<Color?> {
        Binding(
            get: {
                if case .solidColor(let color) = state.backgroundStyle {
                    return color
                }
                return nil
            },
            set: { newColor in
                if let color = newColor {
                    state.snapshotBackgroundState()
                    if state.backgroundPadding <= 0 {
                        state.backgroundPadding = 24
                    }
                    state.backgroundStyle = .solidColor(color)
                    state.commitBackgroundChange()
                }
            }
        )
    }

    // MARK: - Sliders Section

    private var slidersSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            VideoEditorSliderRow(
                label: "Padding",
                value: Binding(
                    get: { state.backgroundPadding },
                    set: { newValue in
                        state.backgroundPadding = newValue
                        if newValue > 0 && state.backgroundStyle == .none {
                            state.backgroundStyle = .solidColor(.white)
                        }
                    }
                ),
                range: 0...300,
                onEditingChanged: { editing in
                    if editing { state.snapshotBackgroundState() }
                    else { state.commitBackgroundChange() }
                }
            )

            VideoEditorSliderRow(
                label: "Shadow",
                value: Binding(
                    get: { state.backgroundShadowIntensity * 100 },
                    set: { state.backgroundShadowIntensity = $0 / 100 }
                ),
                range: 0...100,
                onEditingChanged: { editing in
                    if editing { state.snapshotBackgroundState() }
                    else { state.commitBackgroundChange() }
                }
            )

            VideoEditorSliderRow(
                label: "Corners",
                value: $state.backgroundCornerRadius,
                range: 0...120,
                onEditingChanged: { editing in
                    if editing { state.snapshotBackgroundState() }
                    else { state.commitBackgroundChange() }
                }
            )
        }
    }
}

// MARK: - Wallpaper Thumbnail Button

private struct WallpaperThumbnailButton: View {
    let item: SystemWallpaperManager.WallpaperItem
    let isSelected: Bool
    let action: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        Button(action: action) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.15))
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.4)
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.clear,
                        lineWidth: 2.5
                    )
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        if let cached = SystemWallpaperManager.shared.cachedThumbnail(
            for: item.thumbnailURL ?? item.fullImageURL
        ) {
            thumbnail = cached
            return
        }
        SystemWallpaperManager.shared.loadThumbnail(for: item) { image in
            thumbnail = image
        }
    }
}
