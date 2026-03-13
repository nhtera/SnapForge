import Testing
import Foundation
import AVFoundation
@testable import SnapForge

/// Tests for ScreenRecordingService — state machine and configuration
@MainActor
struct ScreenRecordingServiceTests {

    @Test func sharedInstanceIsSingleton() {
        let a = ScreenRecordingService.shared
        let b = ScreenRecordingService.shared
        #expect(a === b)
    }

    @Test func initialStateIsIdle() {
        let recorder = ScreenRecordingService.shared
        #expect(recorder.state == .idle)
        #expect(recorder.isRecording == false)
        #expect(recorder.isPaused == false)
        #expect(recorder.isActive == false)
    }

    @Test func formattedDurationFormatsCorrectly() {
        let recorder = ScreenRecordingService.shared
        #expect(recorder.formattedDuration == "00:00")
    }

    @Test func stopRecordingWhenIdleReturnsNil() async {
        let recorder = ScreenRecordingService.shared
        let url = await recorder.stopRecording()
        #expect(url == nil, "Stop when idle should return nil")
    }

    @Test func cancelRecordingWhenIdleDoesNotCrash() async {
        let recorder = ScreenRecordingService.shared
        await recorder.cancelRecording()
        #expect(recorder.state == .idle)
    }

    @Test func pauseRecordingWhenIdleDoesNothing() {
        let recorder = ScreenRecordingService.shared
        recorder.pauseRecording()
        #expect(recorder.state == .idle, "Should remain idle")
    }

    @Test func resumeRecordingWhenIdleDoesNothing() {
        let recorder = ScreenRecordingService.shared
        recorder.resumeRecording()
        #expect(recorder.state == .idle, "Should remain idle")
    }

    @Test func togglePauseWhenIdleDoesNothing() {
        let recorder = ScreenRecordingService.shared
        recorder.togglePause()
        #expect(recorder.state == .idle)
    }
}

/// Tests for RecordingSession — thread-safe writer session
struct RecordingSessionTests {

    @Test func resetClearsAllState() {
        let session = RecordingSession()
        session.isCapturing = true
        session.sessionStarted = true

        session.reset()

        #expect(session.isCapturing == false)
        #expect(session.sessionStarted == false)
        #expect(session.assetWriter == nil)
        #expect(session.videoInput == nil)
        #expect(session.audioInput == nil)
        #expect(session.microphoneInput == nil)
        #expect(session.pixelBufferAdaptor == nil)
    }

    @Test func isCapturingIsThreadSafe() async {
        let session = RecordingSession()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    session.isCapturing = (i % 2 == 0)
                    _ = session.isCapturing
                }
            }
        }
        // Test passes if no crash from concurrent access
    }

    @Test func finishWritingWhenNoWriterCompletesQuickly() async {
        let session = RecordingSession()
        await session.finishWriting()
        // Test passes if no hang or crash
    }

    @Test func cancelWritingWhenNoWriterDoesNotCrash() {
        let session = RecordingSession()
        session.cancelWriting()
        // Test passes if no crash
    }

    @Test func finishInputsWhenNoInputsDoesNotCrash() {
        let session = RecordingSession()
        session.finishInputs()
        // Test passes if no crash
    }
}

/// Tests for VideoFormat and VideoQuality enums
struct RecordingTypesTests {

    @Test func videoFormatFileTypes() {
        #expect(VideoFormat.mov.fileExtension == "mov")
        #expect(VideoFormat.mp4.fileExtension == "mp4")
    }

    @Test func videoQualityBitrateMultipliers() {
        #expect(VideoQuality.high.bitrateMultiplier > VideoQuality.medium.bitrateMultiplier)
        #expect(VideoQuality.medium.bitrateMultiplier > VideoQuality.low.bitrateMultiplier)
    }

    @Test func videoFormatCodable() throws {
        let format = VideoFormat.mp4
        let data = try JSONEncoder().encode(format)
        let decoded = try JSONDecoder().decode(VideoFormat.self, from: data)
        #expect(decoded == format)
    }

    @Test func videoQualityCodable() throws {
        let quality = VideoQuality.high
        let data = try JSONEncoder().encode(quality)
        let decoded = try JSONDecoder().decode(VideoQuality.self, from: data)
        #expect(decoded == quality)
    }

    @Test func recordingStateEquality() {
        #expect(RecordingState.idle == RecordingState.idle)
        #expect(RecordingState.idle != RecordingState.recording)
    }

    @Test(arguments: [
        RecordingError.permissionDenied,
        RecordingError.microphonePermissionDenied,
        RecordingError.noDisplayFound,
        RecordingError.setupFailed("test"),
        RecordingError.writeFailed("test"),
        RecordingError.cancelled,
    ])
    func recordingErrorHasDescription(error: RecordingError) throws {
        let description = try #require(error.errorDescription)
        #expect(description.isEmpty == false)
    }
}
