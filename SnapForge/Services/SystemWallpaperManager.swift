import AppKit
import Foundation

/// Loads and caches macOS system wallpapers for use as video backgrounds.
@MainActor @Observable
final class SystemWallpaperManager {
    static let shared = SystemWallpaperManager()

    private(set) var wallpapers: [WallpaperItem] = []
    private(set) var isLoading = false

    private nonisolated(unsafe) let thumbnailCache = NSCache<NSURL, NSImage>()
    private nonisolated(unsafe) let thumbnailSize: CGFloat = 128
    private nonisolated(unsafe) var loadingURLs = Set<URL>()
    private nonisolated(unsafe) let cacheQueue = DispatchQueue(label: "com.snapforge.wallpaper.cache", qos: .userInitiated)

    private nonisolated(unsafe) let systemPaths = [
        "/System/Library/Desktop Pictures",
        "/Library/Desktop Pictures",
    ]

    private nonisolated(unsafe) let supportedExtensions: Set<String> = ["heic", "jpg", "jpeg", "png"]

    // MARK: - Types

    struct WallpaperItem: Identifiable, Hashable {
        let id = UUID()
        let fullImageURL: URL
        let thumbnailURL: URL?
        let name: String

        func hash(into hasher: inout Hasher) {
            hasher.combine(fullImageURL)
        }

        static func == (lhs: WallpaperItem, rhs: WallpaperItem) -> Bool {
            lhs.fullImageURL == rhs.fullImageURL
        }
    }

    // MARK: - Init

    private init() {
        thumbnailCache.countLimit = 100
        thumbnailCache.totalCostLimit = 50 * 1024 * 1024
    }

    // MARK: - Loading

    func loadWallpapers() async {
        guard !isLoading, wallpapers.isEmpty else { return }
        isLoading = true

        let items = await Task.detached(priority: .userInitiated) {
            await self.enumerateSystemWallpapers()
        }.value

        wallpapers = items
        isLoading = false

        // Preload first batch of thumbnails
        for item in items.prefix(12) {
            loadThumbnail(for: item) { _ in }
        }
    }

    // MARK: - Thumbnail Access

    func cachedThumbnail(for url: URL) -> NSImage? {
        thumbnailCache.object(forKey: url as NSURL)
    }

    nonisolated func loadThumbnail(for item: WallpaperItem, completion: @escaping @Sendable (NSImage?) -> Void) {
        let url = item.thumbnailURL ?? item.fullImageURL

        // Check cache
        if let cached = thumbnailCache.object(forKey: url as NSURL) {
            completion(cached)
            return
        }

        // Prevent duplicate loads
        cacheQueue.sync {
            guard !loadingURLs.contains(url) else {
                completion(nil)
                return
            }
            loadingURLs.insert(url)
        }

        // Downsample on background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let thumbnail = self.createDownsampledImage(from: url, maxSize: self.thumbnailSize * 2)

            if let thumbnail {
                self.thumbnailCache.setObject(thumbnail, forKey: url as NSURL)
            }

            self.cacheQueue.sync {
                self.loadingURLs.remove(url)
            }

            DispatchQueue.main.async {
                completion(thumbnail)
            }
        }
    }

    // MARK: - Enumeration

    private nonisolated func enumerateSystemWallpapers() -> [WallpaperItem] {
        var items: [WallpaperItem] = []
        let fm = FileManager.default

        for basePath in systemPaths {
            guard fm.isReadableFile(atPath: basePath) else { continue }

            let baseURL = URL(fileURLWithPath: basePath)
            guard let contents = try? fm.contentsOfDirectory(
                at: baseURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents {
                guard supportedExtensions.contains(url.pathExtension.lowercased()) else { continue }

                let name = url.deletingPathExtension().lastPathComponent

                // Check for pre-existing thumbnail
                let thumbnailDir = baseURL.appendingPathComponent(".thumbnails")
                let thumbnailFile = thumbnailDir
                    .appendingPathComponent(name)
                    .appendingPathExtension("heic")
                let thumbnail = fm.fileExists(atPath: thumbnailFile.path) ? thumbnailFile : nil

                items.append(WallpaperItem(
                    fullImageURL: url,
                    thumbnailURL: thumbnail,
                    name: name
                ))
            }
        }

        return items.sorted { $0.name < $1.name }
    }

    // MARK: - Downsampling

    private nonisolated func createDownsampledImage(from url: URL, maxSize: CGFloat) -> NSImage? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            return nil
        }

        // Clamp max size to source dimensions
        var effectiveMax = maxSize
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
           let h = props[kCGImagePropertyPixelHeight] as? CGFloat {
            effectiveMax = min(maxSize, max(w, h))
        }

        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: effectiveMax,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
