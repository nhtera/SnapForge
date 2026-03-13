import SwiftUI

/// Quick Access Overlay — appears after every capture with quick actions.
struct QuickAccessView: View {
    let capturedImage: NSImage
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            // Image preview — draggable to any app
            Image(nsImage: capturedImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 140)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                .onDrag {
                    let provider = NSItemProvider(object: capturedImage)
                    provider.suggestedName = StorageService().generateImageFilename()
                    return provider
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(4)
                }
                .padding(12)
                .help("Drag to any app")

            Divider()

            // Action buttons
            HStack(spacing: 0) {
                QuickActionButton(icon: "doc.on.clipboard", label: "Copy") {
                    ClipboardService().copyImage(capturedImage)
                    AppCoordinator.shared.dismissQuickAccess()
                }

                Divider().frame(height: 30)

                QuickActionButton(icon: "square.and.arrow.down", label: "Save") {
                    saveImage()
                }

                Divider().frame(height: 30)

                QuickActionButton(icon: "pencil.tip.crop.circle", label: "Annotate") {
                    AppCoordinator.shared.dismissQuickAccess()
                    AppCoordinator.shared.showAnnotationEditor(for: capturedImage)
                }

                Divider().frame(height: 30)

                QuickActionButton(icon: "rectangle.on.rectangle.angled", label: "Mockup") {
                    AppCoordinator.shared.dismissQuickAccess()
                    AppCoordinator.shared.showBackgroundMockup(for: capturedImage)
                }

                Divider().frame(height: 30)

                QuickActionButton(icon: "pin.fill", label: "Pin") {
                    AppCoordinator.shared.dismissQuickAccess()
                    let frame = NSRect(x: 100, y: 100, width: 300, height: 200)
                    AppCoordinator.shared.pinImage(capturedImage, at: frame)
                }

                Divider().frame(height: 30)

                QuickActionButton(icon: "doc.text.viewfinder", label: "OCR") {
                    Task {
                        do {
                            let text = try await OCRService.shared.extractFullText(from: capturedImage)
                            if text.isEmpty {
                                print("⚠️ No text found in image")
                            } else {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(text, forType: .string)
                                print("✅ OCR: copied \(text.count) chars to clipboard")
                            }
                        } catch {
                            print("❌ OCR failed: \(error)")
                        }
                        AppCoordinator.shared.dismissQuickAccess()
                    }
                }

                Divider().frame(height: 30)

                QuickActionButton(icon: "xmark", label: "Close") {
                    AppCoordinator.shared.dismissQuickAccess()
                }
            }
            .frame(height: 50)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
    }

    private func saveImage() {
        let storage = StorageService()
        let filename = storage.generateImageFilename()
        if let _ = try? storage.saveImage(capturedImage, filename: filename) {
            AppCoordinator.shared.dismissQuickAccess()
        }
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(label)
                    .font(.system(size: 10))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovered ? Color.accentColor : Color.primary)
        .background(isHovered ? Color.accentColor.opacity(0.1) : .clear)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
