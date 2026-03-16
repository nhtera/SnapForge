import SwiftUI

/// Quick Access Overlay — appears after every capture with quick actions.
/// Post-capture quick access toolbar with a clean, modern layout.
struct QuickAccessView: View {
    let capturedImage: NSImage
    @State private var isHovering = false
    @State private var autoCloseTask: Task<Void, Never>?
    @State private var hoveredAction: QuickAction?
    @State private var closeHovered = false

    var body: some View {
        VStack(spacing: 0) {
            imagePreview

            actionToolbar
        }
        .frame(width: 380)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
        )
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.16), radius: 12, x: 0, y: 6)
        .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
        .overlay(alignment: .topLeading) {
            closeButton
        }
        .padding(24)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
        .onAppear {
            startAutoCloseTimerIfNeeded()
        }
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                autoCloseTask?.cancel()
            } else {
                startAutoCloseTimerIfNeeded()
            }
        }
        .onDisappear {
            autoCloseTask?.cancel()
        }
    }

    // MARK: - Close Button

    @ViewBuilder
    private var closeButton: some View {
        if isHovering {
            Button {
                AppCoordinator.shared.dismissQuickAccess()
            } label: {
                Circle()
                    .fill(closeHovered ? Color.gray.opacity(0.8) : Color.gray.opacity(0.5))
                    .frame(width: 22, height: 22)
                    .overlay {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .onHover { hovered in
                closeHovered = hovered
            }
            .padding(8)
            .transition(.opacity)
        }
    }

    // MARK: - Image Preview

    private var imagePreview: some View {
        Image(nsImage: capturedImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxHeight: 140)
            .frame(maxWidth: .infinity)
            .clipped()
            .onDrag {
                let provider = NSItemProvider(object: capturedImage)
                provider.suggestedName = AppEnvironment.shared.storageService.generateImageFilename()

                if UserDefaults.standard.bool(forKey: SettingsKey.quickAccessCloseAfterDrag) {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(500))
                        if !NSEvent.modifierFlags.contains(.option) {
                            AppCoordinator.shared.dismissQuickAccess()
                        }
                    }
                }

                return provider
            }
    }

    // MARK: - Action Toolbar

    private var actionToolbar: some View {
        HStack(spacing: 4) {
            ForEach(QuickAction.primaryActions) { action in
                quickActionButton(action)
            }

            // Separator
            RoundedRectangle(cornerRadius: 0.5)
                .fill(.white.opacity(0.1))
                .frame(width: 1, height: 28)
                .padding(.horizontal, 2)

            ForEach(QuickAction.secondaryActions) { action in
                quickActionButton(action)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }

    // MARK: - Action Button

    private func quickActionButton(_ action: QuickAction) -> some View {
        let isActive = hoveredAction == action

        return Button {
            performAction(action)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: action.icon)
                    .font(.system(size: 14, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 24, height: 20)

                Text(action.label)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .foregroundStyle(isActive ? .white : .primary.opacity(0.75))
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? Color.accentColor : .white.opacity(0.05))
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredAction = hovering ? action : nil
            }
        }
        .help(action.tooltip)
    }

    // MARK: - Actions

    private func performAction(_ action: QuickAction) {
        switch action {
        case .copy:
            AppEnvironment.shared.clipboardService.copyImage(capturedImage)
            AppCoordinator.shared.dismissQuickAccess()

        case .save:
            saveImage()

        case .annotate:
            AppCoordinator.shared.dismissQuickAccess()
            AppCoordinator.shared.showAnnotationEditor(for: capturedImage)

        case .mockup:
            AppCoordinator.shared.dismissQuickAccess()
            AppCoordinator.shared.showBackgroundMockup(for: capturedImage)

        case .pin:
            AppCoordinator.shared.dismissQuickAccess()
            let frame = NSRect(x: 100, y: 100, width: 300, height: 200)
            AppCoordinator.shared.pinImage(capturedImage, at: frame)

        case .ocr:
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

        case .blur:
            Task {
                let blurred = await QuickBlurService.shared.autoBlurSensitiveAreas(in: capturedImage)
                AppEnvironment.shared.clipboardService.copyImage(blurred)
                AppCoordinator.shared.dismissQuickAccess()
            }

        case .background:
            let mockup = QuickMockupService.shared.applyLastMockup(to: capturedImage)
            AppEnvironment.shared.clipboardService.copyImage(mockup)
            AppCoordinator.shared.dismissQuickAccess()
        }
    }

    // MARK: - Helpers

    private func saveImage() {
        let storage = AppEnvironment.shared.storageService
        let filename = storage.generateImageFilename()
        if let _ = try? storage.saveImage(capturedImage, filename: filename) {
            AppCoordinator.shared.dismissQuickAccess()
        }
    }

    private func startAutoCloseTimerIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: SettingsKey.quickAccessAutoClose) else { return }
        let timeout = defaults.double(forKey: SettingsKey.quickAccessTimeout)
        let delay = timeout > 0 ? timeout : 5.0

        autoCloseTask?.cancel()
        autoCloseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            AppCoordinator.shared.dismissQuickAccess()
        }
    }
}

// MARK: - Quick Action Model

enum QuickAction: String, CaseIterable, Identifiable {
    case copy, save, annotate, mockup, pin, ocr, blur, background

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .copy: "doc.on.clipboard"
        case .save: "square.and.arrow.down"
        case .annotate: "pencil.tip.crop.circle"
        case .mockup: "macwindow"
        case .pin: "pin"
        case .ocr: "text.viewfinder"
        case .blur: "eye.slash"
        case .background: "sparkles"
        }
    }

    var label: String {
        switch self {
        case .copy: "Copy"
        case .save: "Save"
        case .annotate: "Edit"
        case .mockup: "Mockup"
        case .pin: "Pin"
        case .ocr: "OCR"
        case .blur: "Blur"
        case .background: "BG"
        }
    }

    var tooltip: String {
        switch self {
        case .copy: "Copy to clipboard"
        case .save: "Save to disk"
        case .annotate: "Open annotation editor"
        case .mockup: "Add device mockup"
        case .pin: "Pin on screen"
        case .ocr: "Extract text (OCR)"
        case .blur: "Auto-blur sensitive areas"
        case .background: "Apply background"
        }
    }

    /// Primary actions — most commonly used
    static let primaryActions: [QuickAction] = [.copy, .save, .annotate, .mockup, .pin]

    /// Secondary actions — utilities
    static let secondaryActions: [QuickAction] = [.ocr, .blur, .background]
}
