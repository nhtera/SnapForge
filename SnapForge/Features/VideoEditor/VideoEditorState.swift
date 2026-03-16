import SwiftUI
import AVFoundation
import AVKit

/// Central state management for the SnapForge video editor.
/// Manages video playback, trim range, frame thumbnails, and export state.
@MainActor
@Observable
final class VideoEditorState {

    // MARK: - Video Source

    let videoURL: URL
    let asset: AVURLAsset
    let player: AVPlayer

    // MARK: - Metadata

    private(set) var duration: Double = 0
    private(set) var naturalSize: CGSize = .zero
    private(set) var currentTime: Double = 0
    private(set) var isPlaying = false

    // MARK: - Trim Range

    var trimStart: Double = 0
    var trimEnd: Double = 0

    // MARK: - Frame Thumbnails

    private(set) var frameThumbnails: [NSImage] = []
    private(set) var isExtractingFrames = false

    // MARK: - Export State

    var isExporting = false
    var exportProgress: Double = 0

    // MARK: - Computed Properties

    var trimmedDuration: Double {
        max(0, trimEnd - trimStart)
    }

    var filename: String {
        videoURL.lastPathComponent
    }

    var formattedCurrentTime: String {
        formatTime(currentTime)
    }

    var formattedDuration: String {
        formatTime(duration)
    }

    var formattedTrimmedDuration: String {
        formatTime(trimmedDuration)
    }

    // MARK: - Private

    private var timeObserver: Any?

    // MARK: - Init

    init(url: URL) {
        self.videoURL = url
        self.asset = AVURLAsset(url: url)
        self.player = AVPlayer(url: url)

        setupTimeObserver()
    }

    // MARK: - Setup

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, !self.isExporting else { return }
                self.currentTime = CMTimeGetSeconds(time)

                // Auto-pause at trim end
                if self.currentTime >= self.trimEnd && self.isPlaying {
                    self.pause()
                    self.seek(to: self.trimEnd)
                }
            }
        }
    }

    // MARK: - Metadata Loading

    func loadVideo() async {
        do {
            let dur = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(dur)
            duration = seconds
            trimEnd = seconds

            if let track = try await asset.loadTracks(withMediaType: .video).first {
                let size = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let transformedSize = size.applying(transform)
                naturalSize = CGSize(
                    width: abs(transformedSize.width),
                    height: abs(transformedSize.height)
                )
            }
        } catch {
            print("⚠️ Failed to load video metadata: \(error)")
        }
    }

    // MARK: - Frame Extraction

    func extractFrames() async {
        guard duration > 0 else { return }

        isExtractingFrames = true
        defer { isExtractingFrames = false }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 120, height: 68)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let count = 30
        let interval = duration / Double(count)
        var images: [NSImage] = []

        for i in 0..<count {
            let time = CMTime(seconds: Double(i) * interval, preferredTimescale: 600)
            // Use modern async image generation API (macOS 15+)
            if let (cgImage, _) = try? await generator.image(at: time) {
                let image = NSImage(cgImage: cgImage, size: NSSize(width: 120, height: 68))
                images.append(image)
            }
        }
        frameThumbnails = images
    }

    // MARK: - Playback Control

    func play() {
        if currentTime >= trimEnd || currentTime < trimStart {
            seek(to: trimStart)
        }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlayback() {
        if isPlaying { pause() } else { play() }
    }

    func seek(to time: Double) {
        let clamped = max(trimStart, min(time, trimEnd))
        currentTime = clamped
        player.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    // MARK: - Trim Clamping

    func setTrimStart(_ time: Double) {
        let minDuration = 0.5
        let maxStart = trimEnd - minDuration
        trimStart = max(0, min(time, maxStart))
        if currentTime < trimStart {
            seek(to: trimStart)
        }
    }

    func setTrimEnd(_ time: Double) {
        let minDuration = 0.5
        let minEnd = trimStart + minDuration
        trimEnd = max(minEnd, min(time, duration))
        if currentTime > trimEnd {
            seek(to: trimEnd)
        }
    }

    // MARK: - Formatting

    func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let frac = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", mins, secs, frac)
    }

    // MARK: - Cleanup

    func cleanup() {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
    }
}
