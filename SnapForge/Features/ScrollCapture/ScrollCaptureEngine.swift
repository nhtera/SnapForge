import AppKit
import ScreenCaptureKit

/// Core scroll capture engine — frame capture, overlap detection, and stitching.
/// All image operations use safe CGContext-based copies to avoid IOSurface crashes.
@MainActor
final class ScrollCaptureEngine {

    // MARK: - Frame Capture

    /// Capture a specific rectangular region of the screen, returning a safe deep-copied CGImage.
    /// Excludes windows with the given IDs from the capture (our overlay UI windows).
    func captureFrame(rect: CGRect, excludeWindowIDs: [CGWindowID] = []) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw ScrollCaptureError.noDisplayFound
        }

        // Find SCWindows matching our exclude list
        let excludeWindows = content.windows.filter { window in
            excludeWindowIDs.contains(CGWindowID(window.windowID))
        }

        let filter = SCContentFilter(display: display, excludingWindows: excludeWindows)
        let config = SCStreamConfiguration()

        let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
        config.sourceRect = rect
        config.width = Int(rect.width * scaleFactor)
        config.height = Int(rect.height * scaleFactor)
        config.showsCursor = false
        config.captureResolution = .best

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        // Deep-copy to detach from IOSurface — prevents CFDataGetBytePtr crash
        guard let safeCopy = Self.deepCopy(cgImage) else {
            throw ScrollCaptureError.deepCopyFailed
        }

        return safeCopy
    }

    // MARK: - Safe Deep Copy

    /// Create a new CGImage via CGContext, fully detached from IOSurface backing.
    /// This prevents crashes when accessing pixel data from ScreenCaptureKit images.
    static func deepCopy(_ cgImage: CGImage) -> CGImage? {
        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue |
                         CGBitmapInfo.byteOrder32Little.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    // MARK: - Scroll Simulation

    /// Simulate a mouse scroll event at the given screen position.
    /// In CGEvent scroll wheel: negative wheel1 = scroll DOWN (reveals content below).
    func simulateScroll(amount: Int32, at point: CGPoint) {
        // Method 1: Line-based scroll (more compatible)
        if let lineEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: amount,
            wheel2: 0,
            wheel3: 0
        ) {
            lineEvent.location = point
            lineEvent.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Overlap Detection

    /// Detect pixel overlap using variance-based probe selection.
    /// Finds the most DISTINCTIVE rows in the bottom half of `previous` (rows with highest
    /// pixel variance — text, edges, borders), then searches for those rows in `current`.
    /// This avoids false matches on dark/uniform background rows.
    func detectOverlap(previous: CGImage, current: CGImage) -> Int {
        let width = previous.width
        let height = previous.height

        guard current.width == width, current.height == height else { return 0 }
        guard let prevData = pixelData(from: previous),
              let currData = pixelData(from: current) else { return 0 }

        let bytesPerRow = width * 4

        // Step 1: Compute pixel variance for each row in the bottom 50% of previous frame
        // Variance = sum of absolute differences between adjacent pixels
        let searchStart = height / 2
        var rowVariances: [(row: Int, variance: Int)] = []

        for row in searchStart..<(height - 5) {
            var variance = 0
            let base = row * bytesPerRow
            // Sample pixel differences along the row
            let step = max(width / 100, 2)  // ~100 sample points
            for x in stride(from: step, to: width - step, by: step) {
                let idx = base + x * 4
                let prevIdx = base + (x - step) * 4
                guard idx + 2 < prevData.count, prevIdx + 2 < prevData.count else { continue }

                variance += abs(Int(prevData[idx]) - Int(prevData[prevIdx]))
                variance += abs(Int(prevData[idx + 1]) - Int(prevData[prevIdx + 1]))
                variance += abs(Int(prevData[idx + 2]) - Int(prevData[prevIdx + 2]))
            }
            rowVariances.append((row: row, variance: variance))
        }

        // Step 2: Pick the most distinctive rows (highest variance)
        rowVariances.sort { $0.variance > $1.variance }

        // Take top candidates from different regions to avoid clustering
        var probeRows: [Int] = []
        let minGap = height / 20  // Minimum gap between probes

        for rv in rowVariances {
            if probeRows.allSatisfy({ abs($0 - rv.row) > minGap }) {
                probeRows.append(rv.row)
                if probeRows.count >= 3 { break }
            }
        }

        guard !probeRows.isEmpty else {
            print("📏 Overlap detection: no distinctive rows found")
            return 0
        }

        // Step 3: For each probe row, find its best match in current frame
        // Use full-width SAD comparison for accuracy
        let colStep = max(width / 80, 2)  // ~80 sample columns — dense sampling
        let sampleCols = stride(from: colStep, to: width - colStep, by: colStep).map { $0 }

        var overlapVotes: [Int: Int] = [:]

        for probeRow in probeRows {
            let probeBase = probeRow * bytesPerRow

            var bestMatchRow = -1
            var bestSAD = Int.max

            // Search in top 95% of current frame
            let searchLimit = height * 95 / 100
            for candidateRow in 0..<searchLimit {
                let candBase = candidateRow * bytesPerRow
                var sad = 0

                for col in sampleCols {
                    let pi = probeBase + col * 4
                    let ci = candBase + col * 4
                    guard pi + 2 < prevData.count, ci + 2 < currData.count else { continue }

                    sad += abs(Int(prevData[pi]) - Int(currData[ci]))
                    sad += abs(Int(prevData[pi + 1]) - Int(currData[ci + 1]))
                    sad += abs(Int(prevData[pi + 2]) - Int(currData[ci + 2]))
                }

                if sad < bestSAD {
                    bestSAD = sad
                    bestMatchRow = candidateRow
                }
            }

            guard bestMatchRow >= 0 else { continue }

            // Verify: the match should be very close (pixel-perfect captures)
            let avgSAD = sampleCols.isEmpty ? Int.max : bestSAD / (sampleCols.count * 3)
            guard avgSAD < 10 else { continue }  // strict: < 10 per channel average

            let overlap = height - probeRow + bestMatchRow
            if overlap > 0, overlap < height {
                overlapVotes[overlap, default: 0] += 1
            }
        }

        // Step 4: Pick overlap with most votes
        guard let bestEntry = overlapVotes.max(by: { a, b in
            // Primary: vote count. Secondary: favor higher overlap (smaller scroll)
            if a.value != b.value { return a.value < b.value }
            return a.key < b.key
        }) else {
            print("📏 Overlap detection: no consensus found (votes: \(overlapVotes))")
            return 0
        }

        print("📏 Overlap detection: \(bestEntry.key)px (votes: \(bestEntry.value)/\(probeRows.count), " +
              "probes at rows: \(probeRows), variance top3: \(rowVariances.prefix(3).map { ($0.row, $0.variance) }))")
        return bestEntry.key
    }

    // MARK: - Frame Identity Check

    /// Check if two frames are essentially identical (scroll has reached the end).
    func framesAreIdentical(_ a: CGImage, _ b: CGImage, threshold: Double = 0.98) -> Bool {
        guard a.width == b.width, a.height == b.height else { return false }
        guard let dataA = pixelData(from: a),
              let dataB = pixelData(from: b) else { return false }

        let width = a.width
        let height = a.height
        let bytesPerRow = width * 4

        // Sample a 10x10 grid of points spread evenly across the frame
        let cols = 10
        let rows = 10
        let sampleCount = cols * rows
        var matchCount = 0
        let tolerance: UInt8 = 8

        for i in 0..<sampleCount {
            let col = i % cols
            let row = i / cols
            let x = (width * (2 * col + 1)) / (2 * cols)   // center of each grid cell
            let y = (height * (2 * row + 1)) / (2 * rows)

            guard x >= 0, x < width, y >= 0, y < height else { continue }

            let index = y * bytesPerRow + x * 4
            guard index + 2 < dataA.count, index + 2 < dataB.count else { continue }

            let rMatch = abs(Int(dataA[index]) - Int(dataB[index])) <= tolerance
            let gMatch = abs(Int(dataA[index + 1]) - Int(dataB[index + 1])) <= tolerance
            let bMatch = abs(Int(dataA[index + 2]) - Int(dataB[index + 2])) <= tolerance

            if rMatch && gMatch && bMatch {
                matchCount += 1
            }
        }

        let ratio = Double(matchCount) / Double(sampleCount)
        print("🔍 Frame identity: \(matchCount)/\(sampleCount) match (\(String(format: "%.1f", ratio * 100))%)")
        return ratio >= threshold
    }

    // MARK: - Stitching

    /// Stitch multiple frames vertically with alpha blending in overlap zones.
    /// Returns the final composited NSImage.
    func stitchFrames(_ frames: [CGImage], overlaps: [Int]) -> NSImage? {
        guard !frames.isEmpty else { return nil }
        guard frames.count == overlaps.count + 1 else { return nil }

        let width = frames[0].width

        // Calculate total height
        var totalHeight = frames[0].height
        for i in 1..<frames.count {
            totalHeight += frames[i].height - overlaps[i - 1]
        }

        // Create output pixel buffer
        let bytesPerRow = width * 4
        let totalBytes = bytesPerRow * totalHeight
        var outputData = [UInt8](repeating: 0, count: totalBytes)

        // Extract pixel data for all frames
        var frameDataList: [[UInt8]] = []
        for frame in frames {
            guard let data = pixelData(from: frame) else { return nil }
            frameDataList.append(data)
        }

        // Draw first frame at the top (pixel row 0 = top of output)
        let firstHeight = frames[0].height
        for row in 0..<firstHeight {
            let srcOffset = row * bytesPerRow
            let dstOffset = row * bytesPerRow
            let count = min(bytesPerRow, frameDataList[0].count - srcOffset, totalBytes - dstOffset)
            guard count > 0 else { continue }
            outputData.replaceSubrange(dstOffset..<(dstOffset + count),
                                       with: frameDataList[0][srcOffset..<(srcOffset + count)])
        }

        // Track where next frame starts in output coordinates (top of output = row 0)
        var nextFrameTop = firstHeight

        // Draw subsequent frames with optimal seam-cut in overlap zone
        for i in 1..<frames.count {
            let overlap = overlaps[i - 1]
            let frameHeight = frames[i].height
            let newContentStart = nextFrameTop - overlap

            // Find the best seam row within the overlap zone
            // (the row where previous and current frame match most closely)
            var bestSeamRow = overlap / 2  // default: middle of overlap
            if overlap > 4 {
                var bestSAD = Int.max
                // Sample every 2nd row for performance, skip edges
                let margin = max(overlap / 10, 2)
                for row in stride(from: margin, to: overlap - margin, by: 1) {
                    let outputRow = newContentStart + row
                    guard outputRow >= 0, outputRow < totalHeight else { continue }

                    let prevOffset = outputRow * bytesPerRow
                    let currOffset = row * bytesPerRow
                    var sad = 0

                    // Sample ~30 columns for speed
                    let colStep = max(width / 30, 1)
                    for x in stride(from: colStep, to: width - colStep, by: colStep) {
                        let pi = prevOffset + x * 4
                        let ci = currOffset + x * 4
                        guard pi + 2 < totalBytes, ci + 2 < frameDataList[i].count else { continue }

                        sad += abs(Int(outputData[pi]) - Int(frameDataList[i][ci]))
                        sad += abs(Int(outputData[pi + 1]) - Int(frameDataList[i][ci + 1]))
                        sad += abs(Int(outputData[pi + 2]) - Int(frameDataList[i][ci + 2]))
                    }

                    if sad < bestSAD {
                        bestSAD = sad
                        bestSeamRow = row
                    }
                }
            }

            // Above the seam: keep previous frame content (already in outputData)
            // Below the seam: overwrite with current frame content
            for row in bestSeamRow..<frameHeight {
                let outputRow = newContentStart + row
                guard outputRow >= 0, outputRow < totalHeight else { continue }

                let srcOffset = row * bytesPerRow
                let dstOffset = outputRow * bytesPerRow
                let count = min(bytesPerRow, frameDataList[i].count - srcOffset, totalBytes - dstOffset)
                guard count > 0 else { continue }
                outputData.replaceSubrange(dstOffset..<(dstOffset + count),
                                           with: frameDataList[i][srcOffset..<(srcOffset + count)])
            }

            nextFrameTop = newContentStart + frameHeight
        }

        // Create CGImage from pixel buffer
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue |
                         CGBitmapInfo.byteOrder32Little.rawValue

        guard let provider = CGDataProvider(data: Data(outputData) as CFData),
              let stitchedImage = CGImage(
                width: width,
                height: totalHeight,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else { return nil }

        let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
        return NSImage(
            cgImage: stitchedImage,
            size: NSSize(
                width: Double(width) / scaleFactor,
                height: Double(totalHeight) / scaleFactor
            )
        )
    }

    // MARK: - Pixel Data Helper

    /// Extract raw pixel data from a CGImage.
    private func pixelData(from image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        let totalBytes = bytesPerRow * height

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue |
                         CGBitmapInfo.byteOrder32Little.rawValue

        var data = [UInt8](repeating: 0, count: totalBytes)

        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }
}

// MARK: - Errors

enum ScrollCaptureError: LocalizedError {
    case noDisplayFound
    case deepCopyFailed
    case captureOperationFailed(String)
    case stitchingFailed

    var errorDescription: String? {
        switch self {
        case .noDisplayFound:
            return "No display found for scroll capture."
        case .deepCopyFailed:
            return "Failed to create safe copy of captured frame."
        case .captureOperationFailed(let detail):
            return "Scroll capture failed: \(detail)"
        case .stitchingFailed:
            return "Failed to stitch captured frames."
        }
    }
}
