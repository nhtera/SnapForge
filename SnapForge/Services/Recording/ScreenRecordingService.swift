import AVFoundation
import AppKit
import CoreMedia
import ScreenCaptureKit

// MARK: - Types

enum VideoFormat: String, CaseIterable, Codable {
    case mov, mp4

    var fileType: AVFileType {
        switch self {
        case .mov: return .mov
        case .mp4: return .mp4
        }
    }

    var fileExtension: String { rawValue }
}

enum VideoQuality: String, CaseIterable, Codable {
    case high, medium, low

    var bitrateMultiplier: Int {
        switch self {
        case .high: return 6
        case .medium: return 4
        case .low: return 2
        }
    }
}

enum RecordingState: Equatable {
    case idle, preparing, recording, paused, stopping
}

enum RecordingError: Error, LocalizedError {
    case permissionDenied
    case microphonePermissionDenied
    case noDisplayFound
    case setupFailed(String)
    case writeFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Screen recording permission denied"
        case .microphonePermissionDenied: return "Microphone permission denied"
        case .noDisplayFound: return "No display found"
        case .setupFailed(let msg): return "Setup failed: \(msg)"
        case .writeFailed(let msg): return "Write failed: \(msg)"
        case .cancelled: return "Recording cancelled"
        }
    }
}

// MARK: - Screen Recording Service

@MainActor
@Observable
final class ScreenRecordingService: NSObject {

    static let shared = ScreenRecordingService()

    // MARK: - Observable State

    private(set) var state: RecordingState = .idle
    private(set) var elapsedSeconds: Int = 0
    private(set) var error: RecordingError?

    var formattedDuration: String {
        let mins = elapsedSeconds / 60
        let secs = elapsedSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    var isRecording: Bool { state == .recording }
    var isPaused: Bool { state == .paused }
    var isActive: Bool { state != .idle }

    // MARK: - Recording Components

    private var stream: SCStream?
    private let session = RecordingSession()

    // MARK: - Timing

    private var timerTask: Task<Void, Never>?
    private var startTime: Date?
    private var pausedDuration: TimeInterval = 0
    private var pauseStartTime: Date?

    // MARK: - Configuration

    private var recordingRect: CGRect = .zero
    private var videoFormat: VideoFormat = .mov
    private var videoQuality: VideoQuality = .high
    private var fps: Int = 30
    private var captureSystemAudio: Bool = true
    private var captureMicrophone: Bool = false
    private var showCursor: Bool = true
    private var recordingCodec: AVVideoCodecType = .h264
    private var outputURL: URL?
    private var registeredOutputTypes: Set<SCStreamOutputType> = []
    private var directoryAccess: SandboxFileAccessManager.ScopedAccess?

    // Dedicated queues for each stream type
    private let videoQueue = DispatchQueue(label: "com.snapforge.recording.video", qos: .userInitiated)
    private let audioQueue = DispatchQueue(label: "com.snapforge.recording.audio", qos: .userInteractive)
    private let micQueue = DispatchQueue(label: "com.snapforge.recording.mic", qos: .userInteractive)

    private override init() {
        super.init()
    }

    // MARK: - Public API

    /// Prepare recording with specified parameters
    func prepareRecording(
        rect: CGRect,
        format: VideoFormat = .mov,
        quality: VideoQuality = .high,
        fps: Int = 30,
        captureSystemAudio: Bool = true,
        captureMicrophone: Bool = false,
        showCursor: Bool = true,
        codec: AVVideoCodecType = .h264,
        useRetinaScale: Bool = true,
        saveDirectory: URL
    ) async throws {
        guard state == .idle else { return }
        state = .preparing
        error = nil
        session.sessionStarted = false

        recordingRect = rect
        videoFormat = format
        videoQuality = quality
        self.fps = fps
        self.captureSystemAudio = captureSystemAudio
        self.captureMicrophone = captureMicrophone
        self.showCursor = showCursor
        recordingCodec = codec

        // Load shareable content (will throw if permission not granted)
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            state = .idle
            let message = "Failed to load shareable content: \(error.localizedDescription)"
            self.error = .setupFailed(message)
            throw RecordingError.setupFailed(message)
        }

        // Find target display
        let (display, screen) = findDisplay(for: rect, in: content)
        guard let display else {
            state = .idle
            self.error = .noDisplayFound
            throw RecordingError.noDisplayFound
        }

        let scaleFactor = useRetinaScale ? (screen?.backingScaleFactor ?? 2.0) : 1.0
        let outputWidth = Int(ceil(rect.width * scaleFactor))
        let outputHeight = Int(ceil(rect.height * scaleFactor))

        // Begin scoped access for sandbox — held until cleanup()
        directoryAccess = SandboxFileAccessManager.shared.beginAccessingURL(saveDirectory)

        // Generate output URL
        let filename = generateFileName()
        try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
        outputURL = saveDirectory.appendingPathComponent("\(filename).\(format.fileExtension)")

        // Setup AVAssetWriter
        try setupAssetWriter(width: outputWidth, height: outputHeight)

        // Setup SCStream
        try await setupStream(
            display: display,
            rect: rect,
            screen: screen,
            scaleFactor: scaleFactor,
            content: content
        )
    }

    /// Start the recording
    func startRecording() async throws {
        guard state == .preparing else { return }

        session.assetWriter?.startWriting()

        guard session.assetWriter?.status == .writing else {
            let msg = session.assetWriter?.error?.localizedDescription ?? "Failed to start"
            state = .idle
            self.error = .setupFailed(msg)
            throw RecordingError.setupFailed(msg)
        }

        do {
            try await stream?.startCapture()
        } catch {
            state = .idle
            self.error = .setupFailed(error.localizedDescription)
            throw RecordingError.setupFailed(error.localizedDescription)
        }

        session.isCapturing = true
        state = .recording
        startTime = Date()
        elapsedSeconds = 0
        pausedDuration = 0
        startTimer()

        print("🔴 Recording started \(Int(recordingRect.width))×\(Int(recordingRect.height)) @\(fps)fps")
    }

    /// Pause the recording
    func pauseRecording() {
        guard state == .recording else { return }
        session.isCapturing = false
        pauseStartTime = Date()
        state = .paused
    }

    /// Resume the recording
    func resumeRecording() {
        guard state == .paused, let pauseStart = pauseStartTime else { return }
        pausedDuration += Date().timeIntervalSince(pauseStart)
        pauseStartTime = nil
        session.isCapturing = true
        state = .recording
    }

    /// Toggle pause/resume
    func togglePause() {
        if state == .recording { pauseRecording() }
        else if state == .paused { resumeRecording() }
    }

    /// Stop recording and return the saved URL
    func stopRecording() async -> URL? {
        guard state == .recording || state == .paused else { return nil }

        session.isCapturing = false
        state = .stopping

        timerTask?.cancel()
        timerTask = nil

        // Teardown stream
        if let activeStream = stream {
            await teardownStream(activeStream)
        }

        session.finishInputs()
        await session.finishWriting()

        let url = outputURL
        if let url {
            print("✅ Recording saved: \(url.lastPathComponent) (\(elapsedSeconds)s)")
        }

        cleanup()
        return url
    }

    /// Cancel without saving
    func cancelRecording() async {
        guard state != .idle else { return }

        timerTask?.cancel()
        timerTask = nil

        if let activeStream = stream {
            await teardownStream(activeStream)
        }

        session.cancelWriting()

        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }

        cleanup()
    }

    // MARK: - Private Setup

    private func setupAssetWriter(width: Int, height: Int) throws {
        guard let url = outputURL else {
            throw RecordingError.setupFailed("No output URL")
        }

        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: videoFormat.fileType)
        session.assetWriter = writer

        // Video: H.264
        let bitrate = width * height * videoQuality.bitrateMultiplier
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: recordingCodec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps,
            ],
        ]
        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoIn.expectsMediaDataInRealTime = true
        session.videoInput = videoIn
        writer.add(videoIn)

        // Pixel buffer adaptor for BGRA from SCStream
        let pbAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ]
        session.pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoIn,
            sourcePixelBufferAttributes: pbAttributes
        )

        // System audio: AAC
        if captureSystemAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000,
            ]
            let audioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioIn.expectsMediaDataInRealTime = true
            session.audioInput = audioIn
            writer.add(audioIn)
        }

        // Microphone: AAC mono
        if captureMicrophone {
            let micSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
            ]
            let micIn = AVAssetWriterInput(mediaType: .audio, outputSettings: micSettings)
            micIn.expectsMediaDataInRealTime = true
            session.microphoneInput = micIn
            writer.add(micIn)
        }
    }

    private func setupStream(
        display: SCDisplay,
        rect: CGRect,
        screen: NSScreen?,
        scaleFactor: CGFloat,
        content: SCShareableContent
    ) async throws {
        // Exclude own app from recording
        var excludedApps: [SCRunningApplication] = []
        if let bundleID = Bundle.main.bundleIdentifier {
            excludedApps = content.applications.filter { $0.bundleIdentifier == bundleID }
        }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApps,
            exceptingWindows: []
        )

        let config = SCStreamConfiguration()
        config.queueDepth = 3
        config.width = Int(ceil(rect.width * scaleFactor))
        config.height = Int(ceil(rect.height * scaleFactor))
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = showCursor

        // Area selection → sourceRect
        // The incoming rect is already in CG screen coordinates (Y=0 at top)
        // SCStreamConfiguration.sourceRect also uses CG coordinates
        // Just make it relative to the display's origin
        if let screen {
            let screenFrame = screen.frame
            // Convert absolute screen coords to display-relative coords
            // For CG coords: just subtract screen origin
            let relativeRect = CGRect(
                x: rect.origin.x - screenFrame.origin.x,
                y: rect.origin.y,  // Already in CG top-down coords
                width: rect.width,
                height: rect.height
            )
            let screenBounds = CGRect(x: 0, y: 0, width: screenFrame.width, height: screenFrame.height)
            let clampedRect = relativeRect.intersection(screenBounds)

            guard !clampedRect.isEmpty else {
                throw RecordingError.setupFailed("Selection area is outside display bounds")
            }

            config.sourceRect = clampedRect
            config.width = Int(ceil(clampedRect.width * scaleFactor))
            config.height = Int(ceil(clampedRect.height * scaleFactor))
        }

        // System audio
        if captureSystemAudio {
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 48000
            config.channelCount = 2
        }

        // Microphone (macOS 15+)
        if captureMicrophone {
            let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            switch micStatus {
            case .notDetermined:
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                if !granted { throw RecordingError.microphonePermissionDenied }
            case .denied, .restricted:
                throw RecordingError.microphonePermissionDenied
            case .authorized:
                break
            @unknown default:
                break
            }

            if #available(macOS 15.0, *) {
                config.captureMicrophone = true
                config.microphoneCaptureDeviceID = AVCaptureDevice.default(for: .audio)?.uniqueID
            }
        }

        stream = SCStream(filter: filter, configuration: config, delegate: nil)
        registeredOutputTypes.removeAll()

        try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        registeredOutputTypes.insert(.screen)

        if captureSystemAudio {
            try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
            registeredOutputTypes.insert(.audio)
        }

        if captureMicrophone {
            if #available(macOS 15.0, *) {
                try stream?.addStreamOutput(self, type: .microphone, sampleHandlerQueue: micQueue)
                registeredOutputTypes.insert(.microphone)
            }
        }
    }

    // MARK: - Helpers

    private func findDisplay(for rect: CGRect, in content: SCShareableContent) -> (SCDisplay?, NSScreen?) {
        var targetScreen: NSScreen?
        for screen in NSScreen.screens {
            if screen.frame.intersects(rect) {
                targetScreen = screen
                break
            }
        }

        let targetDisplayID: CGDirectDisplayID
        if let screen = targetScreen,
           let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
            targetDisplayID = displayID
        } else {
            targetDisplayID = CGMainDisplayID()
        }

        let display = content.displays.first(where: { $0.displayID == Int(targetDisplayID) })
            ?? content.displays.first

        return (display, targetScreen)
    }

    private func startTimer() {
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                self?.updateElapsedTime()
            }
        }
    }

    private func updateElapsedTime() {
        guard let start = startTime, state == .recording else { return }
        elapsedSeconds = Int(Date().timeIntervalSince(start) - pausedDuration)
    }

    private func generateFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "SnapForge_Recording_\(formatter.string(from: Date()))"
    }

    private func teardownStream(_ activeStream: SCStream) async {
        for outputType in registeredOutputTypes {
            try? activeStream.removeStreamOutput(self, type: outputType)
        }
        registeredOutputTypes.removeAll()

        try? await activeStream.stopCapture()
        stream = nil
    }

    private func cleanup() {
        timerTask?.cancel()
        timerTask = nil
        startTime = nil
        pauseStartTime = nil
        pausedDuration = 0
        registeredOutputTypes.removeAll()
        session.reset()
        outputURL = nil
        directoryAccess?.stop()
        directoryAccess = nil
        state = .idle
        elapsedSeconds = 0
    }
}

// MARK: - SCStreamOutput

extension ScreenRecordingService: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        autoreleasepool {
            guard sampleBuffer.isValid else { return }

            switch type {
            case .screen:
                session.appendVideoSample(sampleBuffer)
            case .audio:
                session.appendAudioSample(sampleBuffer)
            case .microphone:
                session.appendMicrophoneSample(sampleBuffer)
            @unknown default:
                break
            }
        }
    }
}
