import SwiftUI
import AVFoundation
import AVKit

/// Video trimmer view — trim start/end with timeline scrubber and preview.
struct VideoTrimmerView: View {
    let videoURL: URL
    @State private var player: AVPlayer?
    @State private var duration: Double = 0
    @State private var trimStart: Double = 0
    @State private var trimEnd: Double = 0
    @State private var currentTime: Double = 0
    @State private var isPlaying = false
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Video preview
            if let player = player {
                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding()
            } else {
                Color.black
                    .overlay {
                        ProgressView("Loading video...")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            // Timeline scrubber
            VStack(spacing: 12) {
                // Trim range slider
                HStack(spacing: 8) {
                    Text(formatTime(trimStart))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            // Full track
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 8)

                            // Selected range
                            let startFrac = duration > 0 ? trimStart / duration : 0
                            let endFrac = duration > 0 ? trimEnd / duration : 1
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.accentColor.opacity(0.5))
                                .frame(
                                    width: max(0, (endFrac - startFrac) * geo.size.width),
                                    height: 8
                                )
                                .offset(x: startFrac * geo.size.width)

                            // Playhead
                            let playFrac = duration > 0 ? currentTime / duration : 0
                            Circle()
                                .fill(Color.white)
                                .frame(width: 14, height: 14)
                                .shadow(radius: 2)
                                .offset(x: playFrac * geo.size.width - 7)
                        }
                        .frame(height: 20)
                    }
                    .frame(height: 20)

                    Text(formatTime(trimEnd))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                // Trim controls
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Start")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $trimStart, in: 0...max(0.01, duration)) { editing in
                            if !editing { seekToTime(trimStart) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("End")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $trimEnd, in: 0...max(0.01, duration)) { editing in
                            if !editing { seekToTime(trimEnd) }
                        }
                    }
                }

                // Playback + export buttons
                HStack(spacing: 16) {
                    Button(action: togglePlayback) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("Duration: \(formatTime(max(0, trimEnd - trimStart)))")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Cancel") { dismiss() }
                        .buttonStyle(.plain)

                    Button(action: exportTrimmed) {
                        if isExporting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Label("Export Trimmed", systemImage: "square.and.arrow.up")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isExporting)
                }
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 450)
        .onAppear { loadVideo() }
    }

    // MARK: - Helpers

    private func loadVideo() {
        let avPlayer = AVPlayer(url: videoURL)
        self.player = avPlayer

        Task {
            let asset = AVURLAsset(url: videoURL)
            let dur = try? await asset.load(.duration)
            let seconds = dur.map { CMTimeGetSeconds($0) } ?? 0
            await MainActor.run {
                duration = seconds
                trimEnd = seconds
            }
        }
    }

    private func togglePlayback() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.seek(to: CMTime(seconds: trimStart, preferredTimescale: 600))
            player.play()
        }
        isPlaying.toggle()
    }

    private func seekToTime(_ time: Double) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", mins, secs, ms)
    }

    private func exportTrimmed() {
        isExporting = true

        Task {
            let asset = AVURLAsset(url: videoURL)
            let storage = StorageService()
            let outputFilename = storage.generateVideoFilename(format: "mp4")
            let outputURL = storage.snapForgeDirectory.appendingPathComponent(outputFilename)

            guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
                await MainActor.run { isExporting = false }
                return
            }

            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mp4
            exportSession.timeRange = CMTimeRange(
                start: CMTime(seconds: trimStart, preferredTimescale: 600),
                end: CMTime(seconds: trimEnd, preferredTimescale: 600)
            )

            do {
                try await exportSession.export(to: outputURL, as: .mp4)
                await MainActor.run {
                    isExporting = false
                    print("✅ Trimmed video exported: \(outputURL.lastPathComponent)")
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    print("❌ Export failed: \(error)")
                }
            }
        }
    }
}
