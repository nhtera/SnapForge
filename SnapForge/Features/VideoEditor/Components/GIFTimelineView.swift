import SwiftUI

/// Timeline view for GIF editing with frame-index trim handles.
/// Displays frame thumbnails with draggable start/end handles
/// that map to GIF frame indices.
struct GIFTimelineView: View {
    @Bindable var state: VideoEditorState
    @State private var isDraggingStart = false
    @State private var isDraggingEnd = false

    private let handleWidth: CGFloat = 18
    private let timelineHeight: CGFloat = 56
    private let trimColor = Color.yellow

    private var totalFrames: Int { state.gifFrameCount }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            // Frame labels
            HStack {
                Text("Frame \(state.gifTrimStartFrame)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                // Trimmed frame count indicator
                if state.gifTrimmedFrameCount < totalFrames {
                    HStack(spacing: 2) {
                        Image(systemName: "scissors")
                            .font(.system(size: 9))
                        Text("\(state.gifTrimmedFrameCount) frames")
                            .font(.system(.caption2, design: .monospaced))
                    }
                    .foregroundStyle(trimColor)
                }

                Spacer()

                Text("Frame \(state.gifTrimEndFrame)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Timeline with trim handles
            GeometryReader { geo in
                let trackWidth = geo.size.width
                ZStack(alignment: .leading) {
                    frameStrip(width: trackWidth)
                    dimmedOverlays(trackWidth: trackWidth)
                    trimFrame(trackWidth: trackWidth)

                    // Only show trim handles if more than 1 frame
                    if totalFrames > 1 {
                        trimHandle(isStart: true, trackWidth: trackWidth)
                        trimHandle(isStart: false, trackWidth: trackWidth)
                    }
                }
                .coordinateSpace(name: "gifTimeline")
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
        let startFrac = totalFrames > 1 ? Double(state.gifTrimStartFrame) / Double(totalFrames - 1) : 0
        let endFrac = totalFrames > 1 ? Double(state.gifTrimEndFrame) / Double(totalFrames - 1) : 1

        return ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.black.opacity(0.6))
                .frame(width: max(0, startFrac * trackWidth))

            Rectangle()
                .fill(Color.black.opacity(0.6))
                .frame(width: max(0, (1 - endFrac) * trackWidth))
                .offset(x: endFrac * trackWidth)
        }
    }

    // MARK: - Trim Frame

    private func trimFrame(trackWidth: CGFloat) -> some View {
        let startFrac = totalFrames > 1 ? Double(state.gifTrimStartFrame) / Double(totalFrames - 1) : 0
        let endFrac = totalFrames > 1 ? Double(state.gifTrimEndFrame) / Double(totalFrames - 1) : 1
        let leftEdge = startFrac * trackWidth + handleWidth
        let rightEdge = endFrac * trackWidth - handleWidth
        let frameWidth = max(0, rightEdge - leftEdge)

        return VStack(spacing: 0) {
            Rectangle()
                .fill(trimColor)
                .frame(height: 3)

            Spacer()

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
        let frac = totalFrames > 1
            ? Double(isStart ? state.gifTrimStartFrame : state.gifTrimEndFrame) / Double(totalFrames - 1)
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
            Image(systemName: isStart ? "chevron.compact.left" : "chevron.compact.right")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.5))
        }
        .scaleEffect(y: isDragging ? 1.04 : 1.0)
        .shadow(
            color: isDragging ? trimColor.opacity(0.4) : .clear,
            radius: isDragging ? 6 : 0
        )
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .padding(.horizontal, -10)
        .offset(x: position)
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .named("gifTimeline"))
                .onChanged { value in
                    guard totalFrames > 1 else { return }
                    let fraction = max(0, min(1, value.location.x / trackWidth))
                    let frame = Int(round(fraction * Double(totalFrames - 1)))
                    if isStart {
                        isDraggingStart = true
                        state.setGIFTrimStart(frame)
                    } else {
                        isDraggingEnd = true
                        state.setGIFTrimEnd(frame)
                    }
                }
                .onEnded { _ in
                    isDraggingStart = false
                    isDraggingEnd = false
                }
        )
        .animation(.easeOut(duration: 0.15), value: isDragging)
        .onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
