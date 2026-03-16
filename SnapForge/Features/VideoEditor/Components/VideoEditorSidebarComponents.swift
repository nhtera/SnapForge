import SwiftUI

/// Shared reusable components for video editor sidebars.

// MARK: - Section Header

struct VideoEditorSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Detail Row

struct VideoEditorDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Sidebar Section

struct VideoEditorSidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            VideoEditorSectionHeader(title: title)
            content
        }
    }
}

// MARK: - Slider Row

/// Slider with label + value above, slider below.
struct VideoEditorSliderRow: View {
    let label: String
    @Binding var value: CGFloat
    var range: ClosedRange<CGFloat> = 0...100
    var onEditingChanged: ((Bool) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(value))")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.9))
                    .padding(.horizontal, DesignTokens.Spacing.xs)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.06))
                    )
            }
            Slider(value: $value, in: range) { editing in
                onEditingChanged?(editing)
            }
            .controlSize(.small)
        }
    }
}

// MARK: - Color Swatch Grid

struct VideoEditorColorSwatchGrid: View {
    @Binding var selectedColor: Color?

    private let colors: [Color] = [
        .red, .orange, .yellow, .green, .blue, .purple, .pink, .gray,
        .white, .black,
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 8)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                colorSwatch(color)
            }
        }
    }

    private func colorSwatch(_ color: Color) -> some View {
        Button {
            selectedColor = color
        } label: {
            Circle()
                .fill(color)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Circle()
                        .strokeBorder(
                            selectedColor == color
                                ? Color.accentColor
                                : Color.white.opacity(color == .white ? 0.3 : 0.0),
                            lineWidth: selectedColor == color ? 2.5 : 1
                        )
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Gradient Preset Button

struct VideoEditorGradientPresetButton: View {
    let preset: VideoGradientPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(preset.gradient)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.clear,
                            lineWidth: 2.5
                        )
                }
        }
        .buttonStyle(.plain)
        .help(preset.displayName)
    }
}
