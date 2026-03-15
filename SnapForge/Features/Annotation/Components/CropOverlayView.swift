import SwiftUI

/// Overlay view for crop tool showing crop region, dimming, handles, and grid.
/// Crop overlay with draggable handles for adjusting the crop region.
struct CropOverlayView: View {
  var state: AnnotateState
  let scale: CGFloat
  let imageSize: CGSize

  private let cornerHandleLength: CGFloat = 20
  private let handleThickness: CGFloat = 3

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        if let cropRect = state.cropRect {
          let scaledCrop = scaledCropRect(cropRect)

          // Dim overlay outside crop region
          CropDimOverlay(
            cropRect: scaledCrop,
            containerSize: geometry.size
          )

          // Crop border
          Rectangle()
            .stroke(Color.white, lineWidth: 1.5)
            .frame(width: scaledCrop.width, height: scaledCrop.height)
            .position(x: scaledCrop.midX, y: scaledCrop.midY)
            .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 0)

          // Rule of thirds grid
          cropGrid(in: scaledCrop)

          // Corner L-shaped handles
          ForEach(CropHandle.corners, id: \.self) { handle in
            CropCornerHandleView(handle: handle, length: cornerHandleLength)
              .position(handlePosition(for: handle, in: scaledCrop))
          }

          // Edge handles
          ForEach(CropHandle.edges, id: \.self) { handle in
            CropEdgeHandleView(handle: handle)
              .position(handlePosition(for: handle, in: scaledCrop))
          }

          // Dimension label
          CropDimensionLabel(
            width: Int(cropRect.width),
            height: Int(cropRect.height)
          )
          .position(x: scaledCrop.midX, y: scaledCrop.maxY + 24)
        }
      }
    }
    .allowsHitTesting(false)
  }

  /// Convert image-space crop rect to SwiftUI display coordinates (flipped Y)
  private func scaledCropRect(_ rect: CGRect) -> CGRect {
    CGRect(
      x: rect.origin.x * scale,
      y: (imageSize.height - rect.origin.y - rect.height) * scale,
      width: rect.width * scale,
      height: rect.height * scale
    )
  }

  private func handlePosition(for handle: CropHandle, in rect: CGRect) -> CGPoint {
    switch handle {
    case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
    case .top: return CGPoint(x: rect.midX, y: rect.minY)
    case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
    case .left: return CGPoint(x: rect.minX, y: rect.midY)
    case .right: return CGPoint(x: rect.maxX, y: rect.midY)
    case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
    case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
    case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
    case .body: return CGPoint(x: rect.midX, y: rect.midY)
    }
  }

  @ViewBuilder
  private func cropGrid(in rect: CGRect) -> some View {
    // Vertical lines
    ForEach(1..<3, id: \.self) { i in
      let x = rect.minX + rect.width * CGFloat(i) / 3
      Rectangle()
        .fill(Color.white.opacity(0.4))
        .frame(width: 0.5, height: rect.height)
        .position(x: x, y: rect.midY)
    }

    // Horizontal lines
    ForEach(1..<3, id: \.self) { i in
      let y = rect.minY + rect.height * CGFloat(i) / 3
      Rectangle()
        .fill(Color.white.opacity(0.4))
        .frame(width: rect.width, height: 0.5)
        .position(x: rect.midX, y: y)
    }
  }
}

// MARK: - Dim Overlay

struct CropDimOverlay: View {
  let cropRect: CGRect
  let containerSize: CGSize
  private let dimColor = Color.black.opacity(0.6)

  var body: some View {
    ZStack {
      // Top
      dimColor
        .frame(width: containerSize.width, height: max(0, cropRect.minY))
        .position(x: containerSize.width / 2, y: cropRect.minY / 2)

      // Bottom
      dimColor
        .frame(width: containerSize.width, height: max(0, containerSize.height - cropRect.maxY))
        .position(x: containerSize.width / 2, y: (containerSize.height + cropRect.maxY) / 2)

      // Left
      dimColor
        .frame(width: max(0, cropRect.minX), height: cropRect.height)
        .position(x: cropRect.minX / 2, y: cropRect.midY)

      // Right
      dimColor
        .frame(width: max(0, containerSize.width - cropRect.maxX), height: cropRect.height)
        .position(x: (containerSize.width + cropRect.maxX) / 2, y: cropRect.midY)
    }
  }
}

// MARK: - Corner Handle (L-shaped)

struct CropCornerHandleView: View {
  let handle: CropHandle
  let length: CGFloat
  private let thickness: CGFloat = 3

  var body: some View {
    ZStack {
      // Horizontal bar
      Rectangle()
        .fill(Color.white)
        .frame(width: length, height: thickness)
        .offset(x: horizontalOffset, y: verticalBarY)
        .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 0)

      // Vertical bar
      Rectangle()
        .fill(Color.white)
        .frame(width: thickness, height: length)
        .offset(x: horizontalBarX, y: verticalOffset)
        .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 0)
    }
  }

  private var horizontalOffset: CGFloat {
    switch handle {
    case .topLeft, .bottomLeft: return length / 2
    case .topRight, .bottomRight: return -length / 2
    default: return 0
    }
  }

  private var verticalOffset: CGFloat {
    switch handle {
    case .topLeft, .topRight: return length / 2
    case .bottomLeft, .bottomRight: return -length / 2
    default: return 0
    }
  }

  private var horizontalBarX: CGFloat { 0 }
  private var verticalBarY: CGFloat { 0 }
}

// MARK: - Edge Handle

struct CropEdgeHandleView: View {
  let handle: CropHandle
  private let handleLength: CGFloat = 24
  private let thickness: CGFloat = 3

  var body: some View {
    Rectangle()
      .fill(Color.white)
      .frame(
        width: isHorizontal ? handleLength : thickness,
        height: isHorizontal ? thickness : handleLength
      )
      .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 0)
  }

  private var isHorizontal: Bool {
    handle == .top || handle == .bottom
  }
}

// MARK: - Dimension Label

struct CropDimensionLabel: View {
  let width: Int
  let height: Int

  var body: some View {
    HStack(spacing: 4) {
      Text("\(width)")
        .fontWeight(.medium)
      Text("×")
        .foregroundStyle(.secondary)
      Text("\(height)")
        .fontWeight(.medium)
    }
    .font(.system(size: 11, weight: .regular, design: .monospaced))
    .foregroundStyle(.white)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(
      Capsule()
        .fill(Color.black.opacity(0.75))
    )
  }
}
