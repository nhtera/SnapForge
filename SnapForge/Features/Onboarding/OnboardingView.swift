import SwiftUI

/// Beautiful onboarding screen with permission requests.
struct OnboardingView: View {
    @State private var currentStep = 0
    @State private var permissionService = PermissionService()

    private let steps = [
        OnboardingStep(
            icon: "hammer.fill",
            title: "Welcome to SnapForge",
            subtitle: "Forge perfect captures.",
            description: "The beautiful, blazing-fast screenshot & recording app for Mac."
        ),
        OnboardingStep(
            icon: "rectangle.on.rectangle.angled",
            title: "Screen Recording",
            subtitle: "Required to capture your screen",
            description: "SnapForge needs Screen Recording permission to take screenshots and record your screen."
        ),
        OnboardingStep(
            icon: "mic.fill",
            title: "Microphone",
            subtitle: "Optional – for voice recordings",
            description: "Enable microphone access to record your voice alongside screen recordings."
        ),
        OnboardingStep(
            icon: "camera.fill",
            title: "Camera",
            subtitle: "Optional – for webcam overlay",
            description: "Allow camera access to show your webcam during screen recordings."
        ),
        OnboardingStep(
            icon: "hand.raised.fill",
            title: "Accessibility",
            subtitle: "Optional – for keystroke display",
            description: "Enable Accessibility to show key presses during recordings and enable scrolling capture."
        ),
        OnboardingStep(
            icon: "checkmark.circle.fill",
            title: "You're All Set!",
            subtitle: "Start capturing with SnapForge",
            description: "Use the menu bar icon or press ⌘⇧4 to take your first screenshot."
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: 4) {
                ForEach(0..<steps.count, id: \.self) { index in
                    Capsule()
                        .fill(index <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 3)
                        .animation(.easeInOut, value: currentStep)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)

            Spacer()

            // Step content
            let step = steps[currentStep]

            VStack(spacing: 16) {
                Image(systemName: step.icon)
                    .font(.system(size: 56))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.bounce, value: currentStep)

                Text(step.title)
                    .font(.title)
                    .fontWeight(.bold)

                Text(step.subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Text(step.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
                    .padding(.top, 4)

                // Permission button (for steps 1-4)
                if currentStep >= 1 && currentStep <= 4 {
                    permissionButton(for: currentStep)
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, 40)

            Spacer()

            // Navigation
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if currentStep < steps.count - 1 {
                    Button("Continue") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button("Get Started") {
                        AppCoordinator.shared.dismissOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(width: 600, height: 500)
    }

    @ViewBuilder
    private func permissionButton(for step: Int) -> some View {
        switch step {
        case 1:
            PermissionRow(
                status: permissionService.screenRecordingStatus,
                grantAction: { Task { await permissionService.requestScreenRecording() } },
                refreshAction: { permissionService.checkScreenRecording() }
            )
        case 2:
            PermissionRow(
                status: permissionService.microphoneStatus,
                grantAction: { Task { await permissionService.requestMicrophone() } },
                refreshAction: { permissionService.checkMicrophone() }
            )
        case 3:
            PermissionRow(
                status: permissionService.cameraStatus,
                grantAction: { Task { await permissionService.requestCamera() } },
                refreshAction: { permissionService.checkCamera() }
            )
        case 4:
            PermissionRow(
                status: permissionService.accessibilityStatus,
                grantAction: { permissionService.requestAccessibility() },
                refreshAction: { permissionService.checkAccessibility() }
            )
        default:
            EmptyView()
        }
    }
}

// MARK: - Permission Row

struct PermissionRow: View {
    let status: PermissionService.PermissionStatus
    let grantAction: () -> Void
    let refreshAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .font(.title3)

            Text(status.rawValue)
                .font(.subheadline)
                .foregroundStyle(statusColor)

            Spacer()

            if status != .granted {
                Button("Grant Access") {
                    grantAction()
                }
                .buttonStyle(.bordered)

                Button(action: refreshAction) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private var statusIcon: String {
        switch status {
        case .granted: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .notDetermined: return "questionmark.circle"
        }
    }

    private var statusColor: Color {
        switch status {
        case .granted: return .green
        case .denied: return .red
        case .notDetermined: return .orange
        }
    }
}

// MARK: - Onboarding Step Model

struct OnboardingStep {
    let icon: String
    let title: String
    let subtitle: String
    let description: String
}
