import SwiftUI

/// Area/Window/Fullscreen capture view — full-screen overlay with crosshair.
struct CaptureView: View {
    let mode: CaptureMode
    @State private var viewModel = CaptureViewModel()

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.01)
                .onTapGesture {
                    AppCoordinator.shared.dismissCaptureOverlay()
                }

            // Selection rectangle
            if let selection = viewModel.selectionRect {
                SelectionOverlayView(rect: selection)
            }

            // Crosshair at cursor
            if viewModel.showCrosshair {
                CrosshairView(position: viewModel.cursorPosition)
            }

            // Magnifier
            if viewModel.showMagnifier {
                MagnifierOverlay(position: viewModel.cursorPosition)
            }

            // Mode indicator
            VStack {
                HStack {
                    Spacer()
                    ModeIndicator(mode: mode)
                        .padding(.trailing, 20)
                        .padding(.top, 20)
                }
                Spacer()
            }

            // Dimension display during selection
            if viewModel.isDragging, let rect = viewModel.selectionRect {
                DimensionLabel(rect: rect)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            viewModel.startCapture(mode: mode)
        }
    }
}

// MARK: - Subviews

struct SelectionOverlayView: View {
    let rect: CGRect

    var body: some View {
        Rectangle()
            .stroke(Color.accentColor, lineWidth: 2)
            .background(Color.white.opacity(0.05))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }
}

struct CrosshairView: View {
    let position: CGPoint

    var body: some View {
        ZStack {
            // Vertical line
            Rectangle()
                .fill(Color.accentColor.opacity(0.6))
                .frame(width: 1, height: 40)
                .position(x: position.x, y: position.y)

            // Horizontal line
            Rectangle()
                .fill(Color.accentColor.opacity(0.6))
                .frame(width: 40, height: 1)
                .position(x: position.x, y: position.y)
        }
    }
}

struct MagnifierOverlay: View {
    let position: CGPoint

    var body: some View {
        Circle()
            .stroke(Color.accentColor, lineWidth: 2)
            .background(Circle().fill(.ultraThinMaterial))
            .frame(width: 120, height: 120)
            .position(x: position.x + 80, y: position.y - 80)
    }
}

struct ModeIndicator: View {
    let mode: CaptureMode

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: mode.icon)
            Text(mode.rawValue)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

struct DimensionLabel: View {
    let rect: CGRect

    var body: some View {
        Text("\(Int(rect.width)) × \(Int(rect.height))")
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(.white)
            .position(x: rect.midX, y: rect.maxY + 20)
    }
}
