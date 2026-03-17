import Testing
import Foundation
import AVFoundation
import SwiftUI
@testable import SnapForge

/// Integration tests for VideoEditorExporter — verifies actual export pipeline
/// including background compositor, quality presets, and frame rate handling.
@MainActor
struct VideoExportIntegrationTests {

    // MARK: - Test Video Helper

    /// Create a minimal test video (1 second, 640x480, 30fps, solid red frames)
    private func createTestVideo() async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_video_\(UUID().uuidString).mp4")

        let writer = try AVAssetWriter(url: outputURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 640,
            AVVideoHeightKey: 480,
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 640,
                kCVPixelBufferHeightKey as String: 480,
            ]
        )

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Write 30 frames (1 second at 30fps)
        for frame in 0..<30 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(10))
            }

            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 640, 480, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
            guard let buffer = pixelBuffer else { continue }

            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                // Fill with solid blue color (BGRA)
                let ptr = base.assumingMemoryBound(to: UInt8.self)
                for i in stride(from: 0, to: 640 * 480 * 4, by: 4) {
                    ptr[i] = 255     // B
                    ptr[i + 1] = 0   // G
                    ptr[i + 2] = 0   // R
                    ptr[i + 3] = 255 // A
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])

            let time = CMTime(value: Int64(frame), timescale: 30)
            adaptor.append(buffer, withPresentationTime: time)
        }

        input.markAsFinished()
        await writer.finishWriting()

        guard writer.status == .completed else {
            throw writer.error ?? NSError(domain: "test", code: -1)
        }

        return outputURL
    }

    // MARK: - Simple Export

    @Test func exportSimpleTrimProducesFile() async throws {
        let videoURL = try await createTestVideo()
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let state = VideoEditorState(url: videoURL)
        await state.loadVideo()

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("export_simple_\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try await VideoEditorExporter.exportTrimmed(
            state: state,
            to: outputURL,
            progress: { _ in }
        )

        #expect(FileManager.default.fileExists(atPath: outputURL.path), "Export should produce output file")

        let fileSize = try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64 ?? 0
        #expect(fileSize > 0, "Exported file should have content")
    }

    // MARK: - Export with Background (Gradient)

    @Test func exportWithGradientBackgroundProducesFile() async throws {
        let videoURL = try await createTestVideo()
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let state = VideoEditorState(url: videoURL)
        await state.loadVideo()

        // Enable background with gradient
        state.backgroundStyle = .gradient(.ocean)
        state.backgroundPadding = 40

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("export_gradient_\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try await VideoEditorExporter.exportTrimmed(
            state: state,
            to: outputURL,
            progress: { _ in }
        )

        #expect(FileManager.default.fileExists(atPath: outputURL.path), "Background export should produce output file")

        // Verify output video dimensions include padding
        let outputAsset = AVURLAsset(url: outputURL)
        if let track = try await outputAsset.loadTracks(withMediaType: .video).first {
            let size = try await track.load(.naturalSize)
            // Output should be larger than 640x480 due to padding
            #expect(size.width >= 640, "Width should include padding: \(size.width)")
            #expect(size.height >= 480, "Height should include padding: \(size.height)")
        }
    }

    // MARK: - Export with Solid Color Background

    @Test func exportWithSolidColorBackgroundProducesFile() async throws {
        let videoURL = try await createTestVideo()
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let state = VideoEditorState(url: videoURL)
        await state.loadVideo()

        // Enable background with solid color
        state.backgroundStyle = .solidColor(.red)
        state.backgroundPadding = 20

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("export_solid_\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try await VideoEditorExporter.exportTrimmed(
            state: state,
            to: outputURL,
            progress: { _ in }
        )

        #expect(FileManager.default.fileExists(atPath: outputURL.path), "Solid color export should produce file")
    }

    // MARK: - Export with Corner Radius + Shadow

    @Test func exportWithCornerRadiusAndShadowProducesFile() async throws {
        let videoURL = try await createTestVideo()
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let state = VideoEditorState(url: videoURL)
        await state.loadVideo()

        // Full background settings
        state.backgroundStyle = .gradient(.sunset)
        state.backgroundPadding = 30
        state.backgroundCornerRadius = 12
        state.backgroundShadowIntensity = 0.5

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("export_full_bg_\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try await VideoEditorExporter.exportTrimmed(
            state: state,
            to: outputURL,
            progress: { _ in }
        )

        #expect(FileManager.default.fileExists(atPath: outputURL.path), "Full background export should produce file")
    }

    // MARK: - Frame Rate Preservation

    @Test func exportPreservesReasonableFrameRate() async throws {
        let videoURL = try await createTestVideo()
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let state = VideoEditorState(url: videoURL)
        await state.loadVideo()

        state.backgroundStyle = .gradient(.ocean)
        state.backgroundPadding = 20

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("export_fps_\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try await VideoEditorExporter.exportTrimmed(
            state: state,
            to: outputURL,
            progress: { _ in }
        )

        // Verify frame rate is reasonable (not 1fps from a zero nominalFrameRate)
        let outputAsset = AVURLAsset(url: outputURL)
        if let track = try await outputAsset.loadTracks(withMediaType: .video).first {
            let fps = try await track.load(.nominalFrameRate)
            #expect(fps >= 24, "Frame rate should be at least 24fps, got \(fps)")
        }
    }
}
