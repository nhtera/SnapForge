import XCTest
@testable import SnapForge

/// Tests for ScreenRecordingService — state machine and configuration
@MainActor
final class ScreenRecordingServiceTests: XCTestCase {

    func testSharedInstance_isSingleton() {
        let a = ScreenRecordingService.shared
        let b = ScreenRecordingService.shared
        XCTAssertTrue(a === b)
    }

    func testInitialState_isIdle() {
        let recorder = ScreenRecordingService.shared
        XCTAssertEqual(recorder.state, .idle)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertFalse(recorder.isPaused)
        XCTAssertFalse(recorder.isActive)
    }

    func testFormattedDuration_formatsCorrectly() {
        let recorder = ScreenRecordingService.shared
        // elapsedSeconds is 0 by default
        XCTAssertEqual(recorder.formattedDuration, "00:00")
    }

    func testStopRecording_whenIdle_returnsNil() async {
        let recorder = ScreenRecordingService.shared
        let url = await recorder.stopRecording()
        XCTAssertNil(url, "Stop when idle should return nil")
    }

    func testCancelRecording_whenIdle_doesNotCrash() async {
        let recorder = ScreenRecordingService.shared
        await recorder.cancelRecording()
        XCTAssertEqual(recorder.state, .idle)
    }

    func testPauseRecording_whenIdle_doesNothing() {
        let recorder = ScreenRecordingService.shared
        recorder.pauseRecording()
        XCTAssertEqual(recorder.state, .idle, "Should remain idle")
    }

    func testResumeRecording_whenIdle_doesNothing() {
        let recorder = ScreenRecordingService.shared
        recorder.resumeRecording()
        XCTAssertEqual(recorder.state, .idle, "Should remain idle")
    }

    func testTogglePause_whenIdle_doesNothing() {
        let recorder = ScreenRecordingService.shared
        recorder.togglePause()
        XCTAssertEqual(recorder.state, .idle)
    }
}

/// Tests for RecordingSession — thread-safe writer session
final class RecordingSessionTests: XCTestCase {

    func testReset_clearsAllState() {
        let session = RecordingSession()
        session.isCapturing = true
        session.sessionStarted = true

        session.reset()

        XCTAssertFalse(session.isCapturing)
        XCTAssertFalse(session.sessionStarted)
        XCTAssertNil(session.assetWriter)
        XCTAssertNil(session.videoInput)
        XCTAssertNil(session.audioInput)
        XCTAssertNil(session.microphoneInput)
        XCTAssertNil(session.pixelBufferAdaptor)
    }

    func testIsCapturing_threadSafe() {
        let session = RecordingSession()

        // Access from multiple threads
        let expectation = XCTestExpectation(description: "concurrent access")
        expectation.expectedFulfillmentCount = 100

        for i in 0..<100 {
            DispatchQueue.global().async {
                session.isCapturing = (i % 2 == 0)
                _ = session.isCapturing
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5)
    }

    func testFinishWriting_whenNoWriter_completesQuickly() async {
        let session = RecordingSession()
        // Should not hang or crash
        await session.finishWriting()
        XCTAssertTrue(true)
    }

    func testCancelWriting_whenNoWriter_doesNotCrash() {
        let session = RecordingSession()
        session.cancelWriting()
        XCTAssertTrue(true)
    }

    func testFinishInputs_whenNoInputs_doesNotCrash() {
        let session = RecordingSession()
        session.finishInputs()
        XCTAssertTrue(true)
    }
}

/// Tests for VideoFormat and VideoQuality enums
final class RecordingTypesTests: XCTestCase {

    func testVideoFormat_fileTypes() {
        XCTAssertEqual(VideoFormat.mov.fileExtension, "mov")
        XCTAssertEqual(VideoFormat.mp4.fileExtension, "mp4")
    }

    func testVideoQuality_bitrateMultipliers() {
        XCTAssertGreaterThan(VideoQuality.high.bitrateMultiplier, VideoQuality.medium.bitrateMultiplier)
        XCTAssertGreaterThan(VideoQuality.medium.bitrateMultiplier, VideoQuality.low.bitrateMultiplier)
    }

    func testVideoFormat_codable() throws {
        let format = VideoFormat.mp4
        let data = try JSONEncoder().encode(format)
        let decoded = try JSONDecoder().decode(VideoFormat.self, from: data)
        XCTAssertEqual(decoded, format)
    }

    func testVideoQuality_codable() throws {
        let quality = VideoQuality.high
        let data = try JSONEncoder().encode(quality)
        let decoded = try JSONDecoder().decode(VideoQuality.self, from: data)
        XCTAssertEqual(decoded, quality)
    }

    func testRecordingState_equality() {
        XCTAssertEqual(RecordingState.idle, RecordingState.idle)
        XCTAssertNotEqual(RecordingState.idle, RecordingState.recording)
    }

    func testRecordingError_descriptions() {
        let errors: [RecordingError] = [
            .permissionDenied,
            .microphonePermissionDenied,
            .noDisplayFound,
            .setupFailed("test"),
            .writeFailed("test"),
            .cancelled,
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "\(error) should have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }
}
