import SwiftUI

/// Timeline view with frame thumbnails and draggable trim handles.
/// Inspired by CleanShotX / Snapzy's yellow-bordered trim interface.
struct VideoTimelineView: View {
    @Bindable var state: VideoEditorState
    @State private var isDraggingStart = false
    @State private var isDraggingEnd = false
    @State private var isDraggingPlayhead = false

    private let handleWidth: CGFloat = 12
    private let timelineHeight: CGFloat = 52

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            // Time labels
            HStack {
                Text(state.formatTime(state.trimStart))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(state.formatTime(state.trimEnd))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Timeline with trim handles
            GeometryReader { geo in
                let trackWidth = geo.size.width

                ZStack(alignment: .leading) {
                    // Frame thumbnails strip
                    frameStrip(width: trackWidth)

                    // Dimmed regions outside trim range
                    dimmedOverlays(trackWidth: trackWidth)

                    // Trim border
                    trimBorder(trackWidth: trackWidth)

                    // Left trim handle
                    trimHandle(isStart: true, trackWidth: trackWidth)

                    // Right trim handle
                    trimHandle(isStart: false, trackWidth: trackWidth)

                    // Playhead
                    playheadIndicator(trackWidth: trackWidth)
                }
            }
            .frame(height: timelineHeight)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        }
    }

    // MARK: - Frame Strip

    private func frameStrip(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            if state.frameThumbnails.isEmpty {
                // Loading placeholder
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(Color.gray.opacity(0.15))
                    .overlay {
                        if state.isExtractingFrames {
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                    }
            } else {
                ForEach(Array(state.frameThumbnails.enumerated()), id: \.offset) { _, image in
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(
                            width: width / CGFloat(state.frameThumbnails.count),
                            height: timelineHeight
                        )
                        .clipped()
                }
            }
        }
        .frame(width: width, height: timelineHeight)
    }

    // MARK: - Dimmed Overlays

    private func dimmedOverlays(trackWidth: CGFloat) -> some View {
        let startFrac = state.duration > 0 ? state.trimStart / state.duration : 0
        let endFrac = state.duration > 0 ? state.trimEnd / state.duration : 1

        return ZStack(alignment: .leading) {
            // Left dim
            Rectangle()
                .fill(Color.black.opacity(0.55))
                .frame(width: max(0, startFrac * trackWidth))

            // Right dim
            Rectangle()
                .fill(Color.black.opacity(0.55))
                .frame(width: max(0, (1 - endFrac) * trackWidth))
                .offset(x: endFrac * trackWidth)
        }
    }

    // MARK: - Trim Border

    private func trimBorder(trackWidth: CGFloat) -> some View {
        let startFrac = state.duration > 0 ? state.trimStart / state.duration : 0
        let endFrac = state.duration > 0 ? state.trimEnd / state.duration : 1
        let left = startFrac * trackWidth
        let right = endFrac * trackWidth

        return RoundedRectangle(cornerRadius: 2)
            .strokeBorder(Color.yellow, lineWidth: 2)
            .frame(width: max(0, right - left), height: timelineHeight)
            .offset(x: left)
    }

    // MARK: - Trim Handles

    private func trimHandle(isStart: Bool, trackWidth: CGFloat) -> some View {
        let frac = state.duration > 0
            ? (isStart ? state.trimStart : state.trimEnd) / state.duration
            : (isStart ? 0.0 : 1.0)
        let position = frac * trackWidth - (isStart ? handleWidth : 0)

        return RoundedRectangle(cornerRadius: 3)
            .fill(Color.yellow)
            .frame(width: handleWidth, height: timelineHeight)
            .overlay {
                // Grip lines
                VStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 0.5)
                            .fill(Color.black.opacity(0.3))
                            .frame(width: 4, height: 1)
                    }
                }
            }
            .offset(x: position)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let fraction = max(0, min(1, (value.location.x) / trackWidth))
                        let time = fraction * state.duration
                        if isStart {
                            isDraggingStart = true
                            state.setTrimStart(time)
                        } else {
                            isDraggingEnd = true
                            state.setTrimEnd(time)
                        }
                    }
                    .onEnded { _ in
                        isDraggingStart = false
                        isDraggingEnd = false
                    }
            )
            .cursor(.resizeLeftRight)
    }

    // MARK: - Playhead

    private func playheadIndicator(trackWidth: CGFloat) -> some View {
        let playFrac = state.duration > 0 ? state.currentTime / state.duration : 0

        return Rectangle()
            .fill(Color.white)
            .frame(width: 2, height: timelineHeight)
            .shadow(color: .black.opacity(0.3), radius: 1)
            .offset(x: playFrac * trackWidth - 1)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDraggingPlayhead = true
                        let fraction = max(0, min(1, value.location.x / trackWidth))
                        let time = fraction * state.duration
                        state.seek(to: time)
                    }
                    .onEnded { _ in
                        isDraggingPlayhead = false
                    }
            )
    }
}

// MARK: - Cursor Extension

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { hovering in
            if hovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
