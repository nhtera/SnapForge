import SwiftUI
import ImageIO
import AVFoundation

/// Card view for a single capture item in the History grid.
struct HistoryItemView: View {
    let capture: HistoryCapture
    var viewModel: HistoryViewModel
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
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous))
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
                    ScrollView(.horizontal) {
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
                    .scrollIndicators(.hidden)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Color(white: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
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
            if let image = loadThumbnail(from: capture.filePath) {
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

    /// Loads a downsampled thumbnail. Uses CGImageSource for images and AVAssetImageGenerator for videos.
    private func loadThumbnail(from path: String, maxPixelSize: Int = 200) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()

        // Video files: use AVAssetImageGenerator
        let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "mkv"]
        if videoExtensions.contains(ext) {
            return loadVideoThumbnail(from: url)
        }

        // Image files: use CGImageSource for efficient downsampling
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Extract a single frame thumbnail from a video file.
    private func loadVideoThumbnail(from url: URL) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 200, height: 200)
        guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
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
