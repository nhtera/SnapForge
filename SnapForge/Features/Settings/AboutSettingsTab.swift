import SwiftUI

// MARK: - About Tab

struct AboutSettingsTab: View {
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("SnapForge")
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text("Version \(appVersion) (\(buildNumber))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Forge perfect captures.")
                .font(.body)
                .foregroundStyle(.secondary)

            // Check for Updates
            Button {
                UpdaterManager.shared.checkForUpdates()
            } label: {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Check for Updates")
                }
                .font(.body.weight(.medium))
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.vertical, DesignTokens.Spacing.sm)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            }
            .buttonStyle(.plain)

            Divider()
                .frame(width: 200)

            VStack(spacing: 6) {
                Text("Built with ❤️ by Tien Nguyen")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Link("GitHub", destination: URL(string: "https://github.com/nhtera/SnapForge")!)
                    Link("Releases", destination: URL(string: "https://github.com/nhtera/SnapForge-releases/releases")!)
                }
                .font(.caption)
            }

            Spacer()

            // System info
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
