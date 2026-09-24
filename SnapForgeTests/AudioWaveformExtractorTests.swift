import Testing
import Foundation
import AVFoundation
@testable import SnapForge

// MARK: - Audio Waveform Extractor Tests

@Suite("AudioWaveformExtractor")
struct AudioWaveformExtractorTests {

  /// Writes a 2s mono WAV: first second silent, second second a loud 440 Hz sine.
  private func makeSilenceThenToneWAV() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("waveform-test-\(UUID().uuidString).wav")
    let sampleRate = 44_100.0
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
    let frames = AVAudioFrameCount(sampleRate * 2)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
    buffer.frameLength = frames

    let samples = try #require(buffer.floatChannelData?[0])
    for i in 0..<Int(frames) {
      samples[i] = i < Int(sampleRate) ? 0 : 0.8 * sin(2 * .pi * 440 * Float(i) / Float(sampleRate))
    }

    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
    return url
  }

  @Test func returnsRequestedBucketCountNormalized() async throws {
    let url = try makeSilenceThenToneWAV()
    defer { try? FileManager.default.removeItem(at: url) }

    let amplitudes = await AudioWaveformExtractor.extract(from: url, sampleCount: 40)

    #expect(amplitudes.count == 40)
    #expect(amplitudes.allSatisfy { $0 >= 0 && $0 <= 1 })
    #expect(amplitudes.max() == 1)
  }

  @Test func silentHalfIsQuieterThanToneHalf() async throws {
    let url = try makeSilenceThenToneWAV()
    defer { try? FileManager.default.removeItem(at: url) }

    let amplitudes = await AudioWaveformExtractor.extract(from: url, sampleCount: 40)
    try #require(amplitudes.count == 40)

    // Skip the buckets around the silence→tone boundary
    let silent = amplitudes[0..<18]
    let tone = amplitudes[22..<40]
    #expect(silent.allSatisfy { $0 < 0.05 })
    #expect(tone.allSatisfy { $0 > 0.8 })
  }

  @Test func nonMediaFileReturnsEmpty() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("waveform-test-\(UUID().uuidString).txt")
    try Data("not audio".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let amplitudes = await AudioWaveformExtractor.extract(from: url)
    #expect(amplitudes.isEmpty)
  }
}
