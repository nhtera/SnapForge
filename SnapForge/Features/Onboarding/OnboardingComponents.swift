import SwiftUI

// MARK: - Feature Highlight (Welcome Step)

struct FeatureHighlight: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.blue)
                .frame(width: 24)

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

// MARK: - Permission Row (Permissions Step)

struct OnboardingPermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isRequired: Bool
    let isGranted: Bool
    let onGrant: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                        .fill(.white.opacity(0.08))
                )

            // Title + description
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)

                    Text(isRequired ? "Required" : "Optional")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            isRequired
                                ? Color.orange.opacity(0.3)
                                : Color.white.opacity(0.08)
                        )
                        .foregroundStyle(isRequired ? .orange : .white.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                }

                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer()

            // Action / Status
            if isGranted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.green)
                    Text("Granted")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.green.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            } else {
                Button("Grant Access") {
                    onGrant()
                }
                .buttonStyle(OnboardingPrimaryButton())
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Shortcut Group Card (Shortcuts Step)

struct ShortcutGroupCard: View {
    let title: String
    let shortcuts: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Category label
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.3))
                .tracking(1.2)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

            // Shortcut rows
            VStack(spacing: 0) {
                ForEach(Array(shortcuts.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 12) {
                        // Key badge
                        Text(item.0)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                            .frame(width: 56, alignment: .center)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 6)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                    .fill(.white.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                    .stroke(.white.opacity(0.1), lineWidth: 1)
                            )

                        // Action label
                        Text(item.1)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.65))

                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                    if index < shortcuts.count - 1 {
                        Divider()
                            .background(.white.opacity(0.06))
                            .padding(.horizontal, 14)
                    }
                }
            }
            .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .fill(.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
        }
    }
}

// MARK: - Completion Hint Card

struct CompletionHintCard: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)

                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }
}
