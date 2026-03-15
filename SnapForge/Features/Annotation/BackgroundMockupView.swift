import SwiftUI

/// Background/Mockup tool — add gradient backgrounds, padding, and shadow to screenshots.
struct BackgroundMockupView: View {
    let sourceImage: NSImage
    let onApply: (NSImage) -> Void
    let onCancel: () -> Void

    @State private var selectedPreset: GradientPreset = .ocean
    @State private var padding: CGFloat = 48
    @State private var cornerRadius: CGFloat = 12
    @State private var showShadow = true
    @State private var useCustomColor = false
    @State private var customColor: Color = .white

    var body: some View {
        VStack(spacing: 0) {
            // Live Preview
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()

            Divider()

            // Controls
            controls
                .padding()
        }
        .frame(width: 600, height: 550)
    }

    // MARK: - Preview

    private var preview: some View {
        ZStack {
            // Background
            if useCustomColor {
                RoundedRectangle(cornerRadius: 8)
                    .fill(customColor)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedPreset.gradient)
            }

            // Screenshot with padding + corner radius + shadow
            Image(nsImage: sourceImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .shadow(
                    color: showShadow ? .black.opacity(0.35) : .clear,
                    radius: showShadow ? 20 : 0,
                    y: showShadow ? 10 : 0
                )
                .padding(padding)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 14) {
            // Gradient presets
            HStack(spacing: 8) {
                Text("Background")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .leading)

                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(GradientPreset.allCases) { preset in
                            Button(action: {
                                useCustomColor = false
                                selectedPreset = preset
                            }) {
                                Circle()
                                    .fill(preset.gradient)
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        if !useCustomColor && selectedPreset == preset {
                                            Circle().stroke(.white, lineWidth: 2)
                                        }
                                    }
                                    .shadow(radius: 2)
                            }
                            .buttonStyle(.plain)
                            .help(preset.name)
                        }

                        // Custom color
                        ColorPicker("", selection: $customColor)
                            .labelsHidden()
                            .frame(width: 28, height: 28)
                            .onChange(of: customColor) { _, _ in
                                useCustomColor = true
                            }
                    }
                }
                .scrollIndicators(.hidden)
            }

            // Padding slider
            HStack {
                Text("Padding")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .leading)
                Slider(value: $padding, in: 16...128, step: 4)
                Text("\(Int(padding))pt")
                    .font(.caption.monospacedDigit())
                    .frame(width: 35)
            }

            // Corner radius
            HStack {
                Text("Corners")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .leading)
                Slider(value: $cornerRadius, in: 0...32, step: 2)
                Text("\(Int(cornerRadius))pt")
                    .font(.caption.monospacedDigit())
                    .frame(width: 35)
            }

            // Shadow toggle
            HStack {
                Text("Shadow")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .leading)
                Toggle("", isOn: $showShadow)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
            }

            Divider()

            // Action buttons
            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Copy to Clipboard") {
                    let rendered = renderComposite()
                    AppEnvironment.shared.clipboardService.copyImage(rendered)
                    onCancel()
                }

                Button("Apply") {
                    onApply(renderComposite())
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Render

    /// Render the final composite image (background + padded screenshot).
    private func renderComposite() -> NSImage {
        let imgSize = sourceImage.size
        let totalWidth = imgSize.width + padding * 2
        let totalHeight = imgSize.height + padding * 2

        let compositeImage = NSImage(size: NSSize(width: totalWidth, height: totalHeight))
        compositeImage.lockFocus()

        // Draw background
        let bgRect = NSRect(origin: .zero, size: NSSize(width: totalWidth, height: totalHeight))
        if useCustomColor {
            let nsColor = NSColor(customColor)
            nsColor.setFill()
            NSBezierPath(rect: bgRect).fill()
        } else {
            // Draw gradient
            let gradient = NSGradient(
                starting: NSColor(selectedPreset.colors.first ?? .blue),
                ending: NSColor(selectedPreset.colors.last ?? .purple)
            )
            gradient?.draw(in: bgRect, angle: selectedPreset.angle)
        }

        // Draw shadow
        if showShadow {
            let shadowRect = NSRect(
                x: padding, y: padding,
                width: imgSize.width, height: imgSize.height
            )
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowBlurRadius = 20
            shadow.shadowOffset = NSSize(width: 0, height: -10)
            shadow.set()

            NSColor.clear.setFill()
            let path = NSBezierPath(roundedRect: shadowRect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor.black.withAlphaComponent(0.5).setFill()
            path.fill()

            // Reset shadow
            NSShadow().set()
        }

        // Draw image with corner radius
        let imageRect = NSRect(
            x: padding, y: padding,
            width: imgSize.width, height: imgSize.height
        )
        let clipPath = NSBezierPath(roundedRect: imageRect, xRadius: cornerRadius, yRadius: cornerRadius)
        clipPath.addClip()
        sourceImage.draw(in: imageRect)

        compositeImage.unlockFocus()
        return compositeImage
    }
}

// MARK: - Gradient Presets

enum GradientPreset: String, CaseIterable, Identifiable {
    case ocean, sunset, forest, pastel, warm, cool, dark, neon

    var id: String { rawValue }

    var name: String {
        rawValue.capitalized
    }

    var colors: [Color] {
        switch self {
        case .ocean:  [Color(hex: "667eea"), Color(hex: "764ba2")]
        case .sunset: [Color(hex: "f093fb"), Color(hex: "f5576c")]
        case .forest: [Color(hex: "11998e"), Color(hex: "38ef7d")]
        case .pastel: [Color(hex: "a8edea"), Color(hex: "fed6e3")]
        case .warm:   [Color(hex: "f6d365"), Color(hex: "fda085")]
        case .cool:   [Color(hex: "a1c4fd"), Color(hex: "c2e9fb")]
        case .dark:   [Color(hex: "2c3e50"), Color(hex: "4ca1af")]
        case .neon:   [Color(hex: "fc466b"), Color(hex: "3f5efb")]
        }
    }

    var angle: CGFloat {
        switch self {
        case .ocean:  135
        case .sunset: 90
        case .forest: 45
        case .pastel: 180
        case .warm:   135
        case .cool:   90
        case .dark:   135
        case .neon:   45
        }
    }

    var gradient: LinearGradient {
        LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Color Hex Extension

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
