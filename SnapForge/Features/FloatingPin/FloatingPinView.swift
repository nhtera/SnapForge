import SwiftUI

/// Floating pinned screenshot — stays on top of all windows.
/// Toolbar hidden by default, appears on hover with fade animation.
struct FloatingPinView: View {
    let image: NSImage
    @State private var pinOpacity: Double = 1.0
    @State private var isLocked = false
    @State private var isHovering = false
    @State private var isOCRRunning = false

    var body: some View {
        ZStack(alignment: .top) {
            // Image
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)

            // Toolbar — appears on hover
            if isHovering && !isLocked {
                toolbar
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Lock badge
            if isLocked {
                HStack {
                    Spacer()
                    VStack {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                            .padding(5)
                            .background(.black.opacity(0.6), in: Circle())
                            .padding(6)
                            .onTapGesture { toggleLock() }
                        Spacer()
                    }
                }
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

            // Lock toggle (click-through)
            Button(action: toggleLock) {
                Image(systemName: isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 11))
                    .foregroundColor(isLocked ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .help("Lock: enable click-through")

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
            Button(action: closePin) {
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

    private func findHostWindow() -> NSWindow? {
        NSApp.windows.first { window in
            window.contentView?.subviews.contains(where: { view in
                view is NSHostingView<FloatingPinView>
            }) ?? false
        } ?? NSApp.windows.first { $0.contentView?.hitTest(NSEvent.mouseLocation) != nil && $0.level == .floating }
    }

    private func toggleLock() {
        isLocked.toggle()
        if let window = findHostWindow() {
            window.ignoresMouseEvents = isLocked
        }
    }

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

    private func closePin() {
        if let window = findHostWindow() {
            AppCoordinator.shared.removePin(window)
        }
    }
}
