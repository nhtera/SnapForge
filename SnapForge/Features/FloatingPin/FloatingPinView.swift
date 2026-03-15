import SwiftUI

/// Floating pinned screenshot — stays on top of all windows.
/// Toolbar hidden by default, appears on hover with fade animation.
struct FloatingPinView: View {
    let image: NSImage
    /// Called to close/remove this pin — injected by AppCoordinator
    let onClose: () -> Void

    @State private var pinOpacity: Double = 1.0
    @State private var isHovering = false
    @State private var isOCRRunning = false

    var body: some View {
        ZStack(alignment: .top) {
            // Image — draggable to other apps
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                .onDrag {
                    let provider = NSItemProvider(object: image)
                    provider.suggestedName = "SnapForge_Pin"
                    return provider
                }
                .help("Drag to share with other apps")

            // Toolbar — appears on hover
            if isHovering {
                toolbar
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .opacity(pinOpacity)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            // Opacity slider
            Image(systemName: "sun.max")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Slider(value: $pinOpacity, in: 0.2...1.0)
                .frame(width: 60)

            Divider().frame(height: 16)

            // OCR
            Button(action: runOCR) {
                if isOCRRunning {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 11))
                }
            }
            .buttonStyle(.plain)
            .help("Extract text (OCR)")
            .disabled(isOCRRunning)

            Spacer()

            // Close
            Button(action: { onClose() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(4)
    }

    // MARK: - Actions

    private func runOCR() {
        isOCRRunning = true
        Task {
            do {
                let text = try await OCRService.shared.extractFullText(from: image)
                if !text.isEmpty {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    print("✅ Pin OCR: copied \(text.count) chars")
                } else {
                    print("⚠️ No text found in pinned image")
                }
            } catch {
                print("❌ Pin OCR failed: \(error)")
            }
            isOCRRunning = false
        }
    }
}
