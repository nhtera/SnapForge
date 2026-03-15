import SwiftUI

/// Quick Access Overlay — appears after every capture with quick actions.
/// Redesigned with a clean, modern toolbar-style layout inspired by CleanShotX.
struct QuickAccessView: View {
  let capturedImage: NSImage
  @State private var isHovering = false
  @State private var autoCloseTask: Task<Void, Never>?
  @State private var hoveredAction: QuickAction?

  var body: some View {
    VStack(spacing: 0) {
      // Image preview — draggable to any app
      imagePreview

      // Action toolbar
      actionToolbar
    }
    .background(.ultraThinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    .overlay(
      RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
    )
    .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
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

  // MARK: - Image Preview

  private var imagePreview: some View {
    Image(nsImage: capturedImage)
      .resizable()
      .aspectRatio(contentMode: .fit)
      .frame(maxHeight: 140)
      .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
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
    HStack(spacing: 2) {
      ForEach(QuickAction.primaryActions) { action in
        quickActionButton(action)
      }

      RoundedRectangle(cornerRadius: 0.5)
        .fill(.quaternary)
        .frame(width: 1, height: 20)
        .padding(.horizontal, 2)

      ForEach(QuickAction.secondaryActions) { action in
        quickActionButton(action)
      }
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 6)
  }

  // MARK: - Action Button

  private func quickActionButton(_ action: QuickAction) -> some View {
    Button {
      performAction(action)
    } label: {
      VStack(spacing: 2) {
        Image(systemName: action.icon)
          .font(.system(size: 13, weight: .medium))
          .symbolRenderingMode(.hierarchical)
          .frame(width: 24, height: 20)

        Text(action.label)
          .font(.system(size: 9, weight: .medium))
          .lineLimit(1)
      }
      .frame(width: 44, height: 36)
      .foregroundStyle(
        hoveredAction == action ? Color.accentColor : .primary.opacity(0.75)
      )
      .background(
        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
          .fill(hoveredAction == action ? Color.accentColor.opacity(0.12) : .clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .focusable(false)
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
