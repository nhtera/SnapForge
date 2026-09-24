import AVFoundation

/// Extracts audio amplitude data from a video file for waveform visualization.
enum AudioWaveformExtractor {

    /// Decode rate for analysis — downmixed mono at a low sample rate keeps memory flat
    /// and is plenty of resolution for a few hundred visual bars.
    private static let analysisSampleRate: Double = 8_000

    /// Extract normalized RMS amplitudes from the first audio track.
    /// Returns `sampleCount` Float values (0.0–1.0), or an empty array when there is no audio.
    static func extract(from url: URL, sampleCount: Int = 300) async -> [Float] {
        guard sampleCount > 0 else { return [] }

        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let duration = try? await asset.load(.duration) else {
            return []
        }

        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else { return [] }

        return await Task.detached(priority: .utility) {
            readAmplitudes(
                asset: asset,
                track: track,
                expectedFrames: Int(seconds * analysisSampleRate),
                sampleCount: sampleCount
            )
        }.value
    }

    // MARK: - Private

    /// Streams decoded PCM and accumulates sum-of-squares per visual bucket
    /// (no full-track buffer), then converts to normalized RMS.
    private static func readAmplitudes(
        asset: AVAsset,
        track: AVAssetTrack,
        expectedFrames: Int,
        sampleCount: Int
    ) -> [Float] {
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: analysisSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        guard let reader = try? AVAssetReader(asset: asset) else { return [] }
        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        trackOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(trackOutput) else { return [] }
        reader.add(trackOutput)
        guard reader.startReading() else { return [] }
        defer { reader.cancelReading() }

        let framesPerBucket = max(1, expectedFrames / sampleCount)
        var sumSquares = [Float](repeating: 0, count: sampleCount)
        var counts = [Int](repeating: 0, count: sampleCount)
        var frameIndex = 0
        var chunk: [Float] = []

        while let buffer = trackOutput.copyNextSampleBuffer() {
            if Task.isCancelled { return [] }
            guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { continue }

            let length = CMBlockBufferGetDataLength(blockBuffer)
            let count = length / MemoryLayout<Float>.size
            guard count > 0 else { continue }
            if chunk.count < count { chunk = [Float](repeating: 0, count: count) }

            let status = chunk.withUnsafeMutableBytes { raw in
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { continue }

            for i in 0..<count {
                // Clamp: actual decoded length can slightly exceed the duration-based estimate
                let bucket = min(frameIndex / framesPerBucket, sampleCount - 1)
                sumSquares[bucket] += chunk[i] * chunk[i]
                counts[bucket] += 1
                frameIndex += 1
            }
        }

        guard frameIndex > 0 else { return [] }

        let rms = (0..<sampleCount).map { i in
            counts[i] > 0 ? sqrt(sumSquares[i] / Float(counts[i])) : 0
        }

        // Normalize to 0.0–1.0
        guard let maxVal = rms.max(), maxVal > 0 else { return rms }
        return rms.map { $0 / maxVal }
    }
}
