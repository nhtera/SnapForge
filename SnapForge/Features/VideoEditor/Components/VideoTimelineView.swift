import SwiftUI

/// Timeline view with frame thumbnails and draggable trim handles.
/// Inspired by CleanShotX's wide, easy-to-grab yellow trim handles.
struct VideoTimelineView: View {
    @Bindable var state: VideoEditorState
    @State private var isDraggingStart = false
    @State private var isDraggingEnd = false
    @State private var isDraggingPlayhead = false

    private let handleWidth: CGFloat = 18
    private let timelineHeight: CGFloat = 56
    private let trimColor = Color.yellow

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            // Time labels
            HStack {
                Text(state.formatTime(state.trimStart))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                // Trimmed duration
                if state.trimmedDuration < state.duration {
                    HStack(spacing: 2) {
                        Image(systemName: "scissors")
                            .font(.system(size: 9))
                        Text(state.formattedTrimmedDuration)
                            .font(.system(.caption2, design: .monospaced))
                    }
                    .foregroundStyle(trimColor)
                }

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

                    // Yellow trim frame (top + bottom borders)
                    trimFrame(trackWidth: trackWidth)

                    // Left trim handle
                    trimHandle(isStart: true, trackWidth: trackWidth)

                    // Right trim handle
                    trimHandle(isStart: false, trackWidth: trackWidth)

                    // Playhead
                    playheadIndicator(trackWidth: trackWidth)
                }
                .coordinateSpace(name: "timeline")
            }
            .frame(height: timelineHeight)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Frame Strip

    private func frameStrip(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            if state.frameThumbnails.isEmpty {
                RoundedRectangle(cornerRadius: 6)
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
                .fill(Color.black.opacity(0.6))
                .frame(width: max(0, startFrac * trackWidth))

            // Right dim
            Rectangle()
                .fill(Color.black.opacity(0.6))
                .frame(width: max(0, (1 - endFrac) * trackWidth))
                .offset(x: endFrac * trackWidth)
        }
    }

    // MARK: - Trim Frame (top + bottom yellow borders between handles)

    private func trimFrame(trackWidth: CGFloat) -> some View {
        let startFrac = state.duration > 0 ? state.trimStart / state.duration : 0
        let endFrac = state.duration > 0 ? state.trimEnd / state.duration : 1
        let leftEdge = startFrac * trackWidth + handleWidth
        let rightEdge = endFrac * trackWidth - handleWidth
        let frameWidth = max(0, rightEdge - leftEdge)

        return VStack(spacing: 0) {
            // Top border
            Rectangle()
                .fill(trimColor)
                .frame(height: 3)

            Spacer()

            // Bottom border
            Rectangle()
                .fill(trimColor)
                .frame(height: 3)
        }
        .frame(width: frameWidth, height: timelineHeight)
        .offset(x: leftEdge)
        .allowsHitTesting(false)
    }

    // MARK: - Trim Handles

    private func trimHandle(isStart: Bool, trackWidth: CGFloat) -> some View {
        let frac = state.duration > 0
            ? (isStart ? state.trimStart : state.trimEnd) / state.duration
            : (isStart ? 0.0 : 1.0)
        let position = isStart
            ? frac * trackWidth
            : frac * trackWidth - handleWidth
        let isDragging = isStart ? isDraggingStart : isDraggingEnd

        return UnevenRoundedRectangle(
            topLeadingRadius: isStart ? 6 : 0,
            bottomLeadingRadius: isStart ? 6 : 0,
            bottomTrailingRadius: isStart ? 0 : 6,
            topTrailingRadius: isStart ? 0 : 6
        )
        .fill(trimColor)
        .frame(width: handleWidth, height: timelineHeight)
        .overlay {
            // Chevron grip icon
            Image(systemName: isStart ? "chevron.compact.left" : "chevron.compact.right")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.5))
        }
        .scaleEffect(y: isDragging ? 1.04 : 1.0)
        .shadow(
            color: isDragging ? trimColor.opacity(0.4) : .clear,
            radius: isDragging ? 6 : 0
        )
        // Expand the hit area by padding, then compensate with negative padding
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .padding(.horizontal, -10)
        .offset(x: position)
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .named("timeline"))
                .onChanged { value in
                    let fraction = max(0, min(1, value.location.x / trackWidth))
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
        .animation(.easeOut(duration: 0.15), value: isDragging)
        .cursor(.resizeLeftRight)
    }

    // MARK: - Playhead

    private func playheadIndicator(trackWidth: CGFloat) -> some View {
        let playFrac = state.duration > 0 ? state.currentTime / state.duration : 0

        return ZStack(alignment: .top) {
            // Playhead line
            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: timelineHeight)
                .shadow(color: .black.opacity(0.5), radius: 2)

            // Top knob
            Circle()
                .fill(Color.white)
                .frame(width: 8, height: 8)
                .shadow(color: .black.opacity(0.3), radius: 1)
                .offset(y: -4)
        }
        .offset(x: playFrac * trackWidth - 1)
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .named("timeline"))
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
