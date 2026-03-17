import Testing
import Foundation
import AppKit
@testable import SnapForge

/// Tests for SystemWallpaperManager — singleton, wallpaper loading, thumbnail caching
@MainActor
struct SystemWallpaperManagerTests {

    // MARK: - Singleton

    @Test func sharedIsSingleton() {
        let a = SystemWallpaperManager.shared
        let b = SystemWallpaperManager.shared
        #expect(a === b)
    }

    @Test func sharedHasPublicState() {
        let manager = SystemWallpaperManager.shared
        // Verify observable properties are accessible (type-check test)
        _ = manager.wallpapers
        _ = manager.isLoading
    }

    // MARK: - WallpaperItem

    @Test func wallpaperItemEquality() {
        let url = URL(fileURLWithPath: "/tmp/test.heic")
        let itemA = SystemWallpaperManager.WallpaperItem(fullImageURL: url, thumbnailURL: nil, name: "test")
        let itemB = SystemWallpaperManager.WallpaperItem(fullImageURL: url, thumbnailURL: nil, name: "test")
        #expect(itemA == itemB, "Items with same fullImageURL should be equal")
    }

    @Test func wallpaperItemInequalityDifferentURLs() {
        let urlA = URL(fileURLWithPath: "/tmp/a.heic")
        let urlB = URL(fileURLWithPath: "/tmp/b.heic")
        let itemA = SystemWallpaperManager.WallpaperItem(fullImageURL: urlA, thumbnailURL: nil, name: "a")
        let itemB = SystemWallpaperManager.WallpaperItem(fullImageURL: urlB, thumbnailURL: nil, name: "b")
        #expect(itemA != itemB)
    }

    @Test func wallpaperItemHashConsistentWithEquality() {
        let url = URL(fileURLWithPath: "/tmp/test.heic")
        let itemA = SystemWallpaperManager.WallpaperItem(fullImageURL: url, thumbnailURL: nil, name: "test")
        let itemB = SystemWallpaperManager.WallpaperItem(fullImageURL: url, thumbnailURL: nil, name: "test")
        #expect(itemA.hashValue == itemB.hashValue, "Equal items must have equal hashes")
    }

    @Test func wallpaperItemHasUniqueID() {
        let url = URL(fileURLWithPath: "/tmp/test.heic")
        let itemA = SystemWallpaperManager.WallpaperItem(fullImageURL: url, thumbnailURL: nil, name: "test")
        let itemB = SystemWallpaperManager.WallpaperItem(fullImageURL: url, thumbnailURL: nil, name: "test")
        #expect(itemA.id != itemB.id, "Each item should have a unique UUID")
    }

    // MARK: - Wallpaper Loading

    @Test func loadWallpapersPopulatesList() async {
        let manager = SystemWallpaperManager.shared
        await manager.loadWallpapers()
        // System should have desktop pictures available
        #expect(manager.wallpapers.isEmpty == false, "Should find system wallpapers")
        #expect(manager.isLoading == false, "Should not be loading after completion")
    }

    @Test func loadWallpapersOnlyHEICJPGPNG() async {
        let manager = SystemWallpaperManager.shared
        await manager.loadWallpapers()
        let validExtensions: Set<String> = ["heic", "jpg", "jpeg", "png"]
        for item in manager.wallpapers {
            let ext = item.fullImageURL.pathExtension.lowercased()
            #expect(validExtensions.contains(ext), "Unexpected extension: \(ext) for \(item.name)")
        }
    }

    @Test func wallpapersAreSortedByName() async {
        let manager = SystemWallpaperManager.shared
        await manager.loadWallpapers()
        let names = manager.wallpapers.map(\.name)
        #expect(names == names.sorted(), "Wallpapers should be sorted by name")
    }

    // MARK: - Thumbnail Cache

    @Test func cachedThumbnailReturnsNilForUnknownURL() {
        let manager = SystemWallpaperManager.shared
        let fakeURL = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).heic")
        #expect(manager.cachedThumbnail(for: fakeURL) == nil)
    }

    @Test func loadThumbnailCallsCompletion() async {
        let manager = SystemWallpaperManager.shared
        await manager.loadWallpapers()
        guard let firstItem = manager.wallpapers.first else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            manager.loadThumbnail(for: firstItem) { image in
                // Image may be nil if file can't be downsampled, but completion should fire
                continuation.resume()
            }
        }
    }
}
