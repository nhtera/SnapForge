import AVFoundation
import CoreMedia

/// Thread-safe audio level monitor that computes RMS from audio sample buffers.
/// Throttled to update at ~10 Hz for efficient UI display.
final class AudioLevelMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var _level: Float = 0
    private var lastUpdateTime: CFAbsoluteTime = 0
    private let updateInterval: CFAbsoluteTime = 0.1  // 10 Hz

    var level: Float {
        lock.withLock { _level }
    }

    func processSampleBuffer(_ buffer: CMSampleBuffer) {
        let now = CFAbsoluteTimeGetCurrent()
        // Throttle to 10 Hz
        guard lock.withLock({ now - lastUpdateTime >= updateInterval }) else { return }

        // Verify the audio format is Float32 PCM before accessing sample data.
        // SCStream typically delivers Float32, but if Int16 arrives, bindMemory
        // would read garbage values and produce incorrect levels.
        guard let formatDesc = CMSampleBufferGetFormatDescription(buffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc),
              asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0
        else { return }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { return }

        var lengthAtOffset: Int = 0
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let status = CMBlockBufferGetDataPointer(
            blockBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength, dataPointerOut: &dataPointer
        )
        guard status == kCMBlockBufferNoErr, let data = dataPointer else { return }

        // Compute RMS of float32 samples
        let sampleCount = totalLength / MemoryLayout<Float>.size
        guard sampleCount > 0 else { return }

        let floatPointer = UnsafeRawPointer(data).assumingMemoryBound(to: Float.self)
        var sumSquares: Float = 0
        for i in 0..<sampleCount {
            let sample = floatPointer[i]
            sumSquares += sample * sample
        }

        let rms = sqrt(sumSquares / Float(sampleCount))
        // Convert to 0-1 range using logarithmic scale
        let db = 20 * log10(max(rms, 1e-7))
        let normalized = max(0, min(1, (db + 60) / 60))  // -60dB to 0dB range

        lock.withLock {
            _level = normalized
            lastUpdateTime = now
        }
    }

    func reset() {
        lock.withLock {
            _level = 0
            lastUpdateTime = 0
        }
    }
}
