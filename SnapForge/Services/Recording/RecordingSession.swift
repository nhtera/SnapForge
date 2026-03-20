import AVFoundation
import CoreMedia
import ScreenCaptureKit

/// Thread-safe session managing AVAssetWriter during screen recording.
/// Separated from the main actor-isolated manager for safe access from processing queues.
/// Implements lazy session start: begins when first sample buffer arrives to sync timestamps.
final class RecordingSession: @unchecked Sendable {
    private let lock = NSLock()

    private var _assetWriter: AVAssetWriter?
    private var _videoInput: AVAssetWriterInput?
    private var _pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var _audioInput: AVAssetWriterInput?
    private var _microphoneInput: AVAssetWriterInput?
    private var _sessionStarted = false
    private var _isCapturing = false
    private var _firstTimestamp: CMTime?
    private var _audioLevelMonitor: AudioLevelMonitor?

    init() {}

    var audioLevelMonitor: AudioLevelMonitor? {
        get { lock.withLock { _audioLevelMonitor } }
        set { lock.withLock { _audioLevelMonitor = newValue } }
    }

    // MARK: - Thread-safe accessors

    var assetWriter: AVAssetWriter? {
        get { lock.withLock { _assetWriter } }
        set { lock.withLock { _assetWriter = newValue } }
    }

    var videoInput: AVAssetWriterInput? {
        get { lock.withLock { _videoInput } }
        set { lock.withLock { _videoInput = newValue } }
    }

    var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor? {
        get { lock.withLock { _pixelBufferAdaptor } }
        set { lock.withLock { _pixelBufferAdaptor = newValue } }
    }

    var audioInput: AVAssetWriterInput? {
        get { lock.withLock { _audioInput } }
        set { lock.withLock { _audioInput = newValue } }
    }

    var microphoneInput: AVAssetWriterInput? {
        get { lock.withLock { _microphoneInput } }
        set { lock.withLock { _microphoneInput = newValue } }
    }

    var sessionStarted: Bool {
        get { lock.withLock { _sessionStarted } }
        set { lock.withLock { _sessionStarted = newValue } }
    }

    var isCapturing: Bool {
        get { lock.withLock { _isCapturing } }
        set { lock.withLock { _isCapturing = newValue } }
    }

    // MARK: - Frame Writing

    func appendVideoSample(_ sampleBuffer: CMSampleBuffer) {
        // Validate ScreenCaptureKit frame status
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRaw),
              status == .complete else {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard timestamp.isValid else { return }

        let (writer, videoInput, adaptor, shouldStartSession): (
            AVAssetWriter?, AVAssetWriterInput?, AVAssetWriterInputPixelBufferAdaptor?, Bool
        ) = lock.withLock {
            guard _isCapturing, let writer = _assetWriter, writer.status == .writing else {
                return (nil, nil, nil, false)
            }

            var needsStart = false
            if !_sessionStarted {
                _sessionStarted = true
                _firstTimestamp = timestamp
                needsStart = true
            }

            return (writer, _videoInput, _pixelBufferAdaptor, needsStart)
        }

        guard let writer, let videoInput, let adaptor else { return }

        if shouldStartSession {
            writer.startSession(atSourceTime: timestamp)
            // Verify writer didn't fail (e.g., disk full) during session start
            guard writer.status == .writing else {
                print("⚠️ RecordingSession: Writer failed after startSession: \(writer.error?.localizedDescription ?? "unknown")")
                return
            }
        }

        if videoInput.isReadyForMoreMediaData {
            if !adaptor.append(pixelBuffer, withPresentationTime: timestamp) {
                print("⚠️ RecordingSession: Failed to append video frame")
            }
        }
    }

    func appendAudioSample(_ sampleBuffer: CMSampleBuffer) {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard timestamp.isValid else { return }

        let (audioInput, firstTs, monitor): (AVAssetWriterInput?, CMTime?, AudioLevelMonitor?) = lock.withLock {
            guard _isCapturing, let writer = _assetWriter, writer.status == .writing else {
                return (nil, nil, nil)
            }
            return (_audioInput, _firstTimestamp, _audioLevelMonitor)
        }

        monitor?.processSampleBuffer(sampleBuffer)

        guard let audioInput, let firstTs else { return }
        guard CMTimeCompare(timestamp, firstTs) >= 0 else { return }

        if audioInput.isReadyForMoreMediaData {
            audioInput.append(sampleBuffer)
        }
    }

    func appendMicrophoneSample(_ sampleBuffer: CMSampleBuffer) {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard timestamp.isValid else { return }

        let (micInput, firstTs, monitor): (AVAssetWriterInput?, CMTime?, AudioLevelMonitor?) = lock.withLock {
            guard _isCapturing, let writer = _assetWriter, writer.status == .writing else {
                return (nil, nil, nil)
            }
            return (_microphoneInput, _firstTimestamp, _audioLevelMonitor)
        }

        monitor?.processSampleBuffer(sampleBuffer)

        guard let micInput, let firstTs else { return }
        guard CMTimeCompare(timestamp, firstTs) >= 0 else { return }

        if micInput.isReadyForMoreMediaData {
            micInput.append(sampleBuffer)
        }
    }

    // MARK: - Lifecycle

    func finishInputs() {
        lock.withLock {
            _videoInput?.markAsFinished()
            _audioInput?.markAsFinished()
            _microphoneInput?.markAsFinished()
        }
    }

    func cancelWriting() {
        lock.withLock {
            _assetWriter?.cancelWriting()
        }
    }

    func finishWriting() async {
        let writer = lock.withLock { _assetWriter }
        guard let writer, writer.status == .writing else { return }
        await writer.finishWriting()
    }

    func reset() {
        lock.withLock {
            _assetWriter = nil
            _videoInput = nil
            _pixelBufferAdaptor = nil
            _audioInput = nil
            _microphoneInput = nil
            _sessionStarted = false
            _isCapturing = false
            _firstTimestamp = nil
            _audioLevelMonitor = nil
        }
    }
}
