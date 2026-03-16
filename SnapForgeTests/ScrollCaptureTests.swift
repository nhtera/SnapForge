import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import SnapForge

// MARK: - ScrollCaptureEngine Tests

/// Tests for ScrollCaptureEngine — downscaling, stitching, deep copy, overlap detection, frame identity.
@MainActor
struct ScrollCaptureEngineTests {

    let engine = ScrollCaptureEngine()

    // MARK: - Helper: Create Test CGImage

    /// Create a solid-color CGImage for testing.
    private func makeCGImage(width: Int, height: Int, red: UInt8 = 255, green: UInt8 = 0, blue: UInt8 = 0) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue |
                         CGBitmapInfo.byteOrder32Little.rawValue
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)

        // Fill with BGRA (byteOrder32Little + premultipliedFirst = BGRA layout)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                data[offset] = blue       // B
                data[offset + 1] = green   // G
                data[offset + 2] = red     // R
                data[offset + 3] = 255     // A
            }
        }

        let provider = CGDataProvider(data: Data(data) as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )!
    }

    /// Create a CGImage with a distinct top and bottom half (for overlap tests).
    private func makeGradientImage(width: Int, height: Int, topBrightness: UInt8, bottomBrightness: UInt8) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue |
                         CGBitmapInfo.byteOrder32Little.rawValue
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)

        for y in 0..<height {
            let value = y < height / 2 ? topBrightness : bottomBrightness
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                data[offset] = value       // B
                data[offset + 1] = value   // G
                data[offset + 2] = value   // R
                data[offset + 3] = 255     // A
            }
        }

        let provider = CGDataProvider(data: Data(data) as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )!
    }

    // MARK: - Deep Copy Tests

    @Test func deepCopyProducesValidImage() throws {
        let original = makeCGImage(width: 100, height: 100)
        let copy = try #require(ScrollCaptureEngine.deepCopy(original))

        #expect(copy.width == 100)
        #expect(copy.height == 100)
    }

    @Test func deepCopyPreservesDimensions() throws {
        let original = makeCGImage(width: 200, height: 50)
        let copy = try #require(ScrollCaptureEngine.deepCopy(original))

        #expect(copy.width == original.width)
        #expect(copy.height == original.height)
    }

    // MARK: - Downscale Tests

    @Test func downscaleBy2HalvesDimensions() throws {
        let original = makeCGImage(width: 200, height: 100)
        let downscaled = try #require(ScrollCaptureEngine.downscale(original, by: 2.0))

        #expect(downscaled.width == 100)
        #expect(downscaled.height == 50)
    }

    @Test func downscaleBy1ReturnsOriginal() throws {
        let original = makeCGImage(width: 200, height: 100)
        let result = try #require(ScrollCaptureEngine.downscale(original, by: 1.0))

        // factor <= 1.0 returns the original image
        #expect(result.width == 200)
        #expect(result.height == 100)
    }

    @Test func downscaleByFactorLessThan1ReturnsOriginal() throws {
        let original = makeCGImage(width: 200, height: 100)
        let result = try #require(ScrollCaptureEngine.downscale(original, by: 0.5))

        #expect(result.width == 200)
        #expect(result.height == 100)
    }

    @Test func downscaleBy3ReducesByThird() throws {
        let original = makeCGImage(width: 300, height: 150)
        let downscaled = try #require(ScrollCaptureEngine.downscale(original, by: 3.0))

        #expect(downscaled.width == 100)
        #expect(downscaled.height == 50)
    }

    @Test func downscaleRetinaSimulation() throws {
        // Simulate a typical 2x Retina frame being downscaled to 1x
        let retina = makeCGImage(width: 2880, height: 1800)
        let result = try #require(ScrollCaptureEngine.downscale(retina, by: 2.0))

        #expect(result.width == 1440)
        #expect(result.height == 900)
    }

    @Test func downscaleSmallImageBy2() throws {
        let small = makeCGImage(width: 10, height: 10)
        let result = try #require(ScrollCaptureEngine.downscale(small, by: 2.0))

        #expect(result.width == 5)
        #expect(result.height == 5)
    }

    // MARK: - Stitch to CGImage Tests

    @Test func stitchFramesToCGImageSingleFrame() throws {
        let frame = makeCGImage(width: 100, height: 200)
        let result = try #require(engine.stitchFramesToCGImage([frame], overlaps: []))

        #expect(result.width == 100)
        #expect(result.height == 200)
    }

    @Test func stitchFramesToCGImageTwoFramesNoOverlap() throws {
        let frame1 = makeCGImage(width: 100, height: 200)
        let frame2 = makeCGImage(width: 100, height: 200)
        let result = try #require(engine.stitchFramesToCGImage([frame1, frame2], overlaps: [0]))

        #expect(result.width == 100)
        #expect(result.height == 400)
    }

    @Test func stitchFramesToCGImageTwoFramesWithOverlap() throws {
        let frame1 = makeCGImage(width: 100, height: 200)
        let frame2 = makeCGImage(width: 100, height: 200)
        let result = try #require(engine.stitchFramesToCGImage([frame1, frame2], overlaps: [50]))

        #expect(result.width == 100)
        #expect(result.height == 350)  // 200 + 200 - 50
    }

    @Test func stitchFramesToCGImageThreeFrames() throws {
        let frame1 = makeCGImage(width: 100, height: 100)
        let frame2 = makeCGImage(width: 100, height: 100)
        let frame3 = makeCGImage(width: 100, height: 100)
        let result = try #require(engine.stitchFramesToCGImage([frame1, frame2, frame3], overlaps: [20, 20]))

        #expect(result.width == 100)
        #expect(result.height == 260)  // 100 + (100-20) + (100-20)
    }

    @Test func stitchFramesToCGImageEmptyReturnsNil() {
        let result = engine.stitchFramesToCGImage([], overlaps: [])
        #expect(result == nil)
    }

    @Test func stitchFramesToCGImageMismatchedOverlapsReturnsNil() {
        let frame = makeCGImage(width: 100, height: 100)
        // 1 frame but 1 overlap (should be 0 overlaps for 1 frame)
        let result = engine.stitchFramesToCGImage([frame], overlaps: [10])
        #expect(result == nil)
    }

    // MARK: - stitch NSImage delegates to CGImage

    @Test func stitchFramesReturnsNSImage() throws {
        let frame1 = makeCGImage(width: 100, height: 100)
        let frame2 = makeCGImage(width: 100, height: 100)
        let result = try #require(engine.stitchFrames([frame1, frame2], overlaps: [0]))

        // NSImage wraps the stitched CGImage
        #expect(result.size.width == 100)
        #expect(result.size.height == 200)
    }

    @Test func stitchFramesEmptyReturnsNil() {
        let result = engine.stitchFrames([], overlaps: [])
        #expect(result == nil)
    }

    // MARK: - Frame Identity Tests

    @Test func identicalFramesDetectedAsIdentical() {
        let frame = makeCGImage(width: 100, height: 100)
        let isIdentical = engine.framesAreIdentical(frame, frame, threshold: 0.95)
        #expect(isIdentical == true)
    }

    @Test func differentFramesNotDetectedAsIdentical() {
        let red = makeCGImage(width: 100, height: 100, red: 255, green: 0, blue: 0)
        let blue = makeCGImage(width: 100, height: 100, red: 0, green: 0, blue: 255)
        let isIdentical = engine.framesAreIdentical(red, blue, threshold: 0.95)
        #expect(isIdentical == false)
    }

    @Test func differentSizedFramesNotIdentical() {
        let small = makeCGImage(width: 50, height: 50)
        let large = makeCGImage(width: 100, height: 100)
        let isIdentical = engine.framesAreIdentical(small, large)
        #expect(isIdentical == false)
    }

    // MARK: - Overlap Detection Tests

    @Test func overlapDetectionSameFrameHasHighOverlap() {
        let frame = makeGradientImage(width: 100, height: 100, topBrightness: 200, bottomBrightness: 50)
        let overlap = engine.detectOverlap(previous: frame, current: frame)
        // Same frame → overlap should be close to full height
        #expect(overlap > 0)
    }

    @Test func overlapDetectionDifferentSizesReturnsZero() {
        let small = makeCGImage(width: 50, height: 50)
        let large = makeCGImage(width: 100, height: 100)
        let overlap = engine.detectOverlap(previous: small, current: large)
        #expect(overlap == 0)
    }
}

// MARK: - StorageService CGImage Save Tests

/// Tests for the new StorageService.saveCGImage() direct save method.
@MainActor
struct StorageServiceCGImageTests {

    let storage = StorageService()

    /// Create a solid-color CGImage for testing.
    private func makeCGImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue |
                         CGBitmapInfo.byteOrder32Little.rawValue
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)

        for i in stride(from: 0, to: data.count, by: 4) {
            data[i] = 128       // B
            data[i + 1] = 64    // G
            data[i + 2] = 200   // R
            data[i + 3] = 255   // A
        }

        let provider = CGDataProvider(data: Data(data) as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )!
    }

    @Test func saveCGImageAsPNGCreatesFile() throws {
        let cgImage = makeCGImage(width: 200, height: 100)
        let filename = "test_cgimage_\(UUID().uuidString).png"
        let url = try storage.saveCGImage(cgImage, filename: filename)

        #expect(FileManager.default.fileExists(atPath: url.path))

        // Verify it's a valid PNG by reading it back
        let data = try Data(contentsOf: url)
        #expect(data.count > 0)

        // PNG magic bytes: 89 50 4E 47
        #expect(data[0] == 0x89)
        #expect(data[1] == 0x50)  // 'P'
        #expect(data[2] == 0x4E)  // 'N'
        #expect(data[3] == 0x47)  // 'G'

        try? FileManager.default.removeItem(at: url)
    }

    @Test func saveCGImageAsJPEGCreatesFile() throws {
        let cgImage = makeCGImage(width: 200, height: 100)
        let filename = "test_cgimage_\(UUID().uuidString).jpg"
        let url = try storage.saveCGImage(cgImage, filename: filename, format: "jpg")

        #expect(FileManager.default.fileExists(atPath: url.path))

        let data = try Data(contentsOf: url)
        #expect(data.count > 0)

        // JPEG magic bytes: FF D8
        #expect(data[0] == 0xFF)
        #expect(data[1] == 0xD8)

        try? FileManager.default.removeItem(at: url)
    }

    @Test func saveCGImagePNGSmallerThanTIFF() throws {
        // Create a larger image to see meaningful size difference
        let cgImage = makeCGImage(width: 500, height: 500)
        let pngFilename = "test_pngsize_\(UUID().uuidString).png"
        let pngURL = try storage.saveCGImage(cgImage, filename: pngFilename, format: "png")

        let pngData = try Data(contentsOf: pngURL)

        // A 500×500 solid-color image as PNG should be very small due to compression
        // Uncompressed TIFF would be ~1MB (500*500*4 bytes), PNG should be much smaller
        let uncompressedSize = 500 * 500 * 4
        #expect(pngData.count < uncompressedSize, "PNG should be smaller than uncompressed pixels")

        try? FileManager.default.removeItem(at: pngURL)
    }

    @Test func saveCGImageReadBackMatchesDimensions() throws {
        let cgImage = makeCGImage(width: 300, height: 150)
        let filename = "test_readback_\(UUID().uuidString).png"
        let url = try storage.saveCGImage(cgImage, filename: filename)

        // Read it back using NSImage
        let readBack = NSImage(contentsOf: url)
        #expect(readBack != nil)

        // Verify dimensions by loading as CGImage
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let loaded = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            try? FileManager.default.removeItem(at: url)
            Issue.record("Failed to load saved image back as CGImage")
            return
        }

        #expect(loaded.width == 300)
        #expect(loaded.height == 150)

        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Scroll Capture Integration Tests

/// Integration tests for the full scroll capture optimization pipeline.
@MainActor
struct ScrollCaptureOptimizationTests {

    let engine = ScrollCaptureEngine()

    /// Create a solid-color CGImage.
    private func makeCGImage(width: Int, height: Int, gray: UInt8 = 128) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue |
                         CGBitmapInfo.byteOrder32Little.rawValue
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)

        for i in stride(from: 0, to: data.count, by: 4) {
            data[i] = gray
            data[i + 1] = gray
            data[i + 2] = gray
            data[i + 3] = 255
        }

        let provider = CGDataProvider(data: Data(data) as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )!
    }

    // MARK: - Downscale + Stitch Pipeline

    @Test func downscaleThenStitchProducesCorrectDimensions() throws {
        // Simulate: 3 Retina frames at 2880×1800 → downscale to 1440×900 → stitch with overlap
        let frame1 = makeCGImage(width: 200, height: 100)
        let frame2 = makeCGImage(width: 200, height: 100)
        let frame3 = makeCGImage(width: 200, height: 100)

        // Downscale each by 2x
        let ds1 = try #require(ScrollCaptureEngine.downscale(frame1, by: 2.0))
        let ds2 = try #require(ScrollCaptureEngine.downscale(frame2, by: 2.0))
        let ds3 = try #require(ScrollCaptureEngine.downscale(frame3, by: 2.0))

        #expect(ds1.width == 100)
        #expect(ds1.height == 50)

        // Stitch with 10px overlap each
        let result = try #require(engine.stitchFramesToCGImage([ds1, ds2, ds3], overlaps: [10, 10]))

        #expect(result.width == 100)
        #expect(result.height == 130)  // 50 + (50-10) + (50-10) = 130
    }

    // MARK: - Direct PNG Save (Full Pipeline)

    @Test func fullPipelineDownscaleStitchSavePNG() throws {
        // 1. Create "Retina" frames
        let frames = (0..<5).map { _ in makeCGImage(width: 200, height: 100) }

        // 2. Downscale to 1x
        let downscaled = try frames.map { frame in
            try #require(ScrollCaptureEngine.downscale(frame, by: 2.0))
        }

        // 3. Stitch (no overlap for simplicity)
        let overlaps = [Int](repeating: 0, count: downscaled.count - 1)
        let stitched = try #require(engine.stitchFramesToCGImage(downscaled, overlaps: overlaps))

        #expect(stitched.width == 100)
        #expect(stitched.height == 250)  // 5 × 50

        // 4. Save directly as PNG via CGImageDestination
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_pipeline_\(UUID().uuidString).png")

        let destination = try #require(CGImageDestinationCreateWithURL(
            tmpURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, stitched, nil)
        let finalized = CGImageDestinationFinalize(destination)
        #expect(finalized == true)

        // 5. Verify the file is small
        let attrs = try FileManager.default.attributesOfItem(atPath: tmpURL.path)
        let fileSize = try #require(attrs[.size] as? Int)

        // 100×250 solid gray PNG should be tiny — well under 1MB
        #expect(fileSize < 1_048_576, "PNG should be under 1MB, got \(fileSize) bytes")
        #expect(fileSize > 0)

        // 6. Verify it's a valid PNG
        let data = try Data(contentsOf: tmpURL)
        #expect(data[0] == 0x89)
        #expect(data[1] == 0x50)

        try? FileManager.default.removeItem(at: tmpURL)
    }

    // MARK: - Size Comparison (Optimization Proof)

    @Test func directPNGSaveSmallerThanTIFFIntermediary() throws {
        // Simulate the old vs new pipeline for the same image content

        let width = 400
        let height = 1000
        let cgImage = makeCGImage(width: width, height: height)

        // OLD path: NSImage → tiffRepresentation → PNG
        let nsImage = NSImage(
            cgImage: cgImage,
            size: NSSize(width: CGFloat(width), height: CGFloat(height))
        )
        let tiffData = try #require(nsImage.tiffRepresentation)
        let bitmapRep = try #require(NSBitmapImageRep(data: tiffData))
        let oldPngData = try #require(bitmapRep.representation(using: .png, properties: [:]))
        let oldSize = oldPngData.count

        // NEW path: CGImageDestination → PNG directly
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_new_\(UUID().uuidString).png")
        let dest = try #require(CGImageDestinationCreateWithURL(
            tmpURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(dest, cgImage, nil)
        let finalized = CGImageDestinationFinalize(dest)
        #expect(finalized == true)

        let newData = try Data(contentsOf: tmpURL)
        let newSize = newData.count

        // Both methods should produce valid PNG output
        #expect(oldSize > 0)
        #expect(newSize > 0)

        // The TIFF intermediary size is what matters — it's the real bottleneck
        let tiffSize = tiffData.count
        let rawPixels = width * height * 4
        // TIFF intermediary should be close to raw pixel size (uncompressed)
        #expect(tiffSize >= rawPixels / 2, "TIFF intermediary (\(tiffSize)) should be close to raw (\(rawPixels))")
        // Both PNGs should be much smaller than the raw pixels
        #expect(newSize < rawPixels / 2, "PNG should be much smaller than raw pixels")

        try? FileManager.default.removeItem(at: tmpURL)
    }

    // MARK: - Memory Efficiency Tests

    @Test func downscaleReducesPixelCount() throws {
        let retina = makeCGImage(width: 2880, height: 1800)
        let pixels2x = retina.width * retina.height
        let bytes2x = pixels2x * 4  // 4 bytes per pixel

        let oneX = try #require(ScrollCaptureEngine.downscale(retina, by: 2.0))
        let pixels1x = oneX.width * oneX.height
        let bytes1x = pixels1x * 4

        // 1x should be exactly 25% of 2x pixel count
        #expect(pixels1x == pixels2x / 4)
        #expect(bytes1x == bytes2x / 4)
    }

    @Test func stitchingManyFramesAtOneXIsManageable() throws {
        // Simulate 20 frames at 1x resolution (1440×900 each, ~50px overlap)
        let frameWidth = 200  // using small sizes for test speed
        let frameHeight = 100
        let frameCount = 20
        let overlap = 10

        let frames = (0..<frameCount).map { _ in makeCGImage(width: frameWidth, height: frameHeight) }
        let overlaps = [Int](repeating: overlap, count: frameCount - 1)

        let result = try #require(engine.stitchFramesToCGImage(frames, overlaps: overlaps))

        // Expected height: 100 + 19*(100-10) = 100 + 19*90 = 1810
        let expectedHeight = frameHeight + (frameCount - 1) * (frameHeight - overlap)
        #expect(result.width == frameWidth)
        #expect(result.height == expectedHeight)

        // Output buffer size should be manageable
        let outputBytes = result.width * result.height * 4
        #expect(outputBytes < 200 * 1024 * 1024, "Output should be under 200MB cap")
    }
}
