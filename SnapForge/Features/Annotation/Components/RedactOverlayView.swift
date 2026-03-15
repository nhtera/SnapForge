import SwiftUI

/// Overlay shown when the Redact tool is active.
/// Displays detected sensitive regions for user review before applying.
struct RedactOverlayView: View {
  @Bindable var state: AnnotateState
  let scale: CGFloat
  let imageSize: CGSize

  var body: some View {
    ZStack {
      // Detected regions with selection highlights
      ForEach($state.redactRegions) { $region in
        let displayRect = scaledRect(region.bounds)

        Rectangle()
          .fill(region.isSelected
            ? Color(nsColor: region.type.color).opacity(0.3)
            : Color.gray.opacity(0.1)
          )
          .overlay(
            Rectangle()
              .stroke(
                region.isSelected
                  ? Color(nsColor: region.type.color)
                  : Color.gray.opacity(0.5),
                lineWidth: region.isSelected ? 2 : 1
              )
          )
          .overlay(alignment: .topLeading) {
            HStack(spacing: 3) {
              Image(systemName: region.type.icon)
                .font(.system(size: 9))
              Text(region.type.displayName)
                .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color(nsColor: region.type.color), in: Capsule())
            .offset(x: 2, y: -14)
          }
          .frame(width: displayRect.width, height: displayRect.height)
          .position(
            x: displayRect.midX,
            y: displayRect.midY
          )
          .onTapGesture {
            region.isSelected.toggle()
          }
      }

      // Bottom toolbar
      VStack {
        Spacer()
        redactToolbar
          .padding(.bottom, 16)
      }
    }
    .frame(width: imageSize.width * scale, height: imageSize.height * scale)
  }

  // MARK: - Toolbar

  private var redactToolbar: some View {
    HStack(spacing: 12) {
      let selectedCount = state.redactRegions.filter(\.isSelected).count
      let totalCount = state.redactRegions.count

      Text("\(selectedCount)/\(totalCount) selected")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))

      Button(action: { toggleAll() }) {
        Label(
          selectedCount == totalCount ? "Deselect All" : "Select All",
          systemImage: selectedCount == totalCount ? "checkmark.circle" : "circle"
        )
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
      }
      .buttonStyle(.plain)

      Button(action: { state.cancelRedact() }) {
        Label("Cancel", systemImage: "xmark")
          .font(.system(size: 12, weight: .medium))
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
      }
      .buttonStyle(.plain)

      Button(action: { state.applyRedactions() }) {
        Label("Apply Redact", systemImage: "eye.slash.fill")
          .font(.system(size: 12, weight: .medium))
          .padding(.horizontal, 14)
          .padding(.vertical, 6)
          .background(Color.red, in: RoundedRectangle(cornerRadius: 8))
          .foregroundStyle(.white)
      }
      .buttonStyle(.plain)
      .disabled(selectedCount == 0)
    }
  }

  // MARK: - Helpers

  private func scaledRect(_ rect: CGRect) -> CGRect {
    CGRect(
      x: rect.origin.x * scale,
      y: rect.origin.y * scale,
      width: rect.width * scale,
      height: rect.height * scale
    )
  }

  private func toggleAll() {
    let allSelected = state.redactRegions.allSatisfy(\.isSelected)
    for i in state.redactRegions.indices {
      state.redactRegions[i].isSelected = !allSelected
    }
  }
}
