import SwiftUI

/// Comparison mode for the screen diff tool.
enum DiffMode: String, CaseIterable, Identifiable {
  case sideBySide
  case overlay
  case difference

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .sideBySide: "Side by Side"
    case .overlay: "Overlay"
    case .difference: "Diff"
    }
  }

  var icon: String {
    switch self {
    case .sideBySide: "square.split.2x1"
    case .overlay: "square.stack"
    case .difference: "square.split.diagonal"
    }
  }
}

/// Screen Diff view — compare two screenshots with multiple visualization modes.
struct ScreenDiffView: View {
  @State var imageA: NSImage?
  @State var imageB: NSImage?
  @State private var diffMode: DiffMode = .sideBySide
  @State private var overlayOpacity: Double = 0.5
  @State private var sliderPosition: CGFloat = 0.5
  @State private var diffImage: NSImage?
  @State private var diffPercentage: Double = 0

  var body: some View {
    VStack(spacing: 0) {
      // Toolbar
      diffToolbar
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)

      Divider()

      // Comparison area
      if let imageA, let imageB {
        ZStack {
          switch diffMode {
          case .sideBySide:
            sideBySideView(imageA: imageA, imageB: imageB)
          case .overlay:
            overlayView(imageA: imageA, imageB: imageB)
          case .difference:
            differenceView(imageA: imageA, imageB: imageB)
          }
        }
      } else {
        dropZonesView
      }
    }
    .onAppear { generateDiff() }
    .onChange(of: diffMode) { generateDiff() }
  }

  // MARK: - Toolbar

  private var diffToolbar: some View {
    HStack(spacing: 12) {
      Picker("Mode", selection: $diffMode) {
        ForEach(DiffMode.allCases) { mode in
          Label(mode.displayName, systemImage: mode.icon).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .frame(maxWidth: 300)

      Spacer()

      if diffMode == .overlay {
        HStack(spacing: 6) {
          Text("Slider")
            .font(.caption)
            .foregroundStyle(.secondary)
          Slider(value: $sliderPosition, in: 0...1)
            .frame(width: 120)
          Text("\(Int(sliderPosition * 100))%")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: 30)
        }
      }

      if diffMode == .difference {
        Text("\(String(format: "%.1f", diffPercentage))% different")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(.ultraThinMaterial, in: Capsule())
      }

      // Swap button
      Button(action: {
        let temp = imageA
        imageA = imageB
        imageB = temp
        generateDiff()
      }) {
        Image(systemName: "arrow.left.arrow.right")
      }
      .help("Swap Images")
    }
  }

  // MARK: - Side by Side

  private func sideBySideView(imageA: NSImage, imageB: NSImage) -> some View {
    HStack(spacing: 2) {
      VStack(spacing: 4) {
        Text("Before")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.secondary)
        ScrollView([.horizontal, .vertical]) {
          Image(nsImage: imageA)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .padding(12)
        }
      }
      Divider()
      VStack(spacing: 4) {
        Text("After")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.secondary)
        ScrollView([.horizontal, .vertical]) {
          Image(nsImage: imageB)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .padding(12)
        }
      }
    }
  }

  // MARK: - Overlay (Before/After Wipe Slider)

  private func overlayView(imageA: NSImage, imageB: NSImage) -> some View {
    GeometryReader { geo in
      let imageSize = fitSize(for: imageA.size, in: geo.size, padding: 40)
      let imageOrigin = CGPoint(
        x: (geo.size.width - imageSize.width) / 2,
        y: (geo.size.height - imageSize.height) / 2
      )
      let clipX = imageOrigin.x + imageSize.width * sliderPosition

      ZStack {
        // Image B (right/after) — full
        Image(nsImage: imageB)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: imageSize.width, height: imageSize.height)
          .position(x: geo.size.width / 2, y: geo.size.height / 2)

        // Image A (left/before) — clipped to slider position
        Image(nsImage: imageA)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: imageSize.width, height: imageSize.height)
          .position(x: geo.size.width / 2, y: geo.size.height / 2)
          .clipShape(
            HalfClip(splitX: clipX, geo: geo.size)
          )

        // Divider line
        Rectangle()
          .fill(Color.white)
          .frame(width: 2, height: imageSize.height)
          .position(x: clipX, y: geo.size.height / 2)
          .shadow(color: .black.opacity(0.5), radius: 2)

        // Slider handle
        ZStack {
          Circle()
            .fill(Color.white)
            .frame(width: 28, height: 28)
            .shadow(color: .black.opacity(0.3), radius: 3)
          Image(systemName: "arrow.left.and.right")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
        }
        .position(x: clipX, y: geo.size.height / 2)

        // Labels
        Text("Before")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Color.black.opacity(0.5), in: Capsule())
          .position(x: imageOrigin.x + 40, y: imageOrigin.y + 16)

        Text("After")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Color.black.opacity(0.5), in: Capsule())
          .position(x: imageOrigin.x + imageSize.width - 36, y: imageOrigin.y + 16)
      }
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            let relativeX = (value.location.x - imageOrigin.x) / imageSize.width
            sliderPosition = min(1, max(0, relativeX))
          }
      )
    }
  }

  /// Calculate fitted image size with padding
  private func fitSize(for imageSize: NSSize, in containerSize: CGSize, padding: CGFloat) -> CGSize {
    let availableWidth = containerSize.width - padding * 2
    let availableHeight = containerSize.height - padding * 2
    let scale = min(availableWidth / imageSize.width, availableHeight / imageSize.height, 1)
    return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
  }

  // MARK: - Difference

  private func differenceView(imageA: NSImage, imageB: NSImage) -> some View {
    Group {
      if let diff = diffImage {
        ScrollView([.horizontal, .vertical]) {
          Image(nsImage: diff)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .padding(20)
        }
      } else {
        VStack(spacing: 8) {
          ProgressView()
          Text("Computing pixel diff…")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  // MARK: - Drop Zones

  private var dropZonesView: some View {
    HStack(spacing: 16) {
      dropZone(label: "Image A", image: imageA) { url in
        imageA = NSImage(contentsOf: url)
        generateDiff()
      }
      dropZone(label: "Image B", image: imageB) { url in
        imageB = NSImage(contentsOf: url)
        generateDiff()
      }
    }
    .padding(40)
  }

  private func dropZone(label: String, image: NSImage?, onDrop: @escaping (URL) -> Void) -> some View {
    VStack(spacing: 12) {
      if let image {
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(maxHeight: 300)
      } else {
        Image(systemName: "photo.badge.plus")
          .font(.system(size: 40))
          .foregroundStyle(.secondary)
        Text("Drop \(label) here")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
        .foregroundStyle(Color.secondary.opacity(0.3))
    }
  }

  // MARK: - Diff Computation

  private func generateDiff() {
    guard diffMode == .difference,
          let imageA, let imageB else { return }

    Task {
      let result = await Task.detached(priority: .userInitiated) {
        computePixelDiff(imageA: imageA, imageB: imageB)
      }.value
      self.diffImage = result.image
      self.diffPercentage = result.percentage
    }
  }
}

// MARK: - Pixel Diff Computation (nonisolated)

/// Compute pixel-level difference between two images.
/// Returns a heatmap image and the percentage of differing pixels.
private func computePixelDiff(
  imageA: NSImage, imageB: NSImage
) -> (image: NSImage?, percentage: Double) {
  guard let tiffA = imageA.tiffRepresentation,
        let tiffB = imageB.tiffRepresentation,
        let ciA = CIImage(data: tiffA),
        let ciB = CIImage(data: tiffB) else {
    return (nil, 0)
  }

  // Compute pixel difference using CIDifferenceBlendMode
  let diffFilter = CIFilter(name: "CIDifferenceBlendMode")
  diffFilter?.setValue(ciA, forKey: kCIInputImageKey)
  diffFilter?.setValue(ciB, forKey: kCIInputBackgroundImageKey)
  guard let diffOutput = diffFilter?.outputImage else { return (nil, 0) }

  // Amplify the diff for visibility
  let colorControls = CIFilter(name: "CIColorControls")
  colorControls?.setValue(diffOutput, forKey: kCIInputImageKey)
  colorControls?.setValue(3.0, forKey: kCIInputContrastKey)
  colorControls?.setValue(1.5, forKey: kCIInputBrightnessKey)
  guard let amplified = colorControls?.outputImage else { return (nil, 0) }

  // Render to NSImage
  let context = CIContext()
  guard let cgImage = context.createCGImage(amplified, from: amplified.extent) else {
    return (nil, 0)
  }

  let result = NSImage(
    cgImage: cgImage,
    size: NSSize(width: imageA.size.width, height: imageA.size.height)
  )

  // Estimate percentage of differing pixels (sample-based)
  let percentage = estimateDiffPercentage(diffOutput: diffOutput, context: context)

  return (result, percentage)
}

/// Sample-based diff percentage estimation for performance.
private func estimateDiffPercentage(diffOutput: CIImage, context: CIContext) -> Double {
  let extent = diffOutput.extent
  guard extent.width > 0, extent.height > 0 else { return 0 }

  // Sample at lower resolution for performance
  let sampleWidth = min(Int(extent.width), 200)
  let sampleHeight = min(Int(extent.height), 200)

  var pixelData = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
  context.render(
    diffOutput,
    toBitmap: &pixelData,
    rowBytes: sampleWidth * 4,
    bounds: CGRect(x: extent.origin.x, y: extent.origin.y,
                   width: CGFloat(sampleWidth), height: CGFloat(sampleHeight)),
    format: .RGBA8,
    colorSpace: CGColorSpaceCreateDeviceRGB()
  )

  let threshold: UInt8 = 10
  var diffCount = 0
  let totalPixels = sampleWidth * sampleHeight
  for i in stride(from: 0, to: pixelData.count, by: 4) {
    if pixelData[i] > threshold || pixelData[i + 1] > threshold || pixelData[i + 2] > threshold {
      diffCount += 1
    }
  }

  return Double(diffCount) / Double(totalPixels) * 100
}

// MARK: - Half Clip Shape

/// Clips content to show only the left portion up to splitX.
struct HalfClip: Shape {
  var splitX: CGFloat
  var geo: CGSize

  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.addRect(CGRect(x: rect.minX, y: rect.minY, width: splitX, height: rect.height))
    return path
  }
}
