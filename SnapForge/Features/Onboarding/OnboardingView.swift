import SwiftUI
import AVFoundation

// MARK: - Onboarding Flow (4 steps, adapted from Snapzy)

struct OnboardingView: View {
    @State private var currentStep = 0
    @State private var permissionService = PermissionService()

    private let totalSteps = 4

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(white: 0.08),
                    Color(white: 0.12),
                    Color(white: 0.08),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Content
            Group {
                switch currentStep {
                case 0:
                    welcomeStep
                case 1:
                    permissionsStep
                case 2:
                    shortcutsStep
                case 3:
                    completionStep
                default:
                    EmptyView()
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            // Page indicator dots
            if currentStep > 0 {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        ForEach(0..<totalSteps, id: \.self) { index in
                            Circle()
                                .fill(index == currentStep ? Color.white : Color.white.opacity(0.3))
                                .frame(width: 7, height: 7)
                                .animation(.easeInOut(duration: 0.3), value: currentStep)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(width: 600, height: 560)
        .preferredColorScheme(.dark)
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            // App icon
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
                .shadow(color: .blue.opacity(0.3), radius: 20, y: 8)

            Text("SnapForge")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)

            Text("The beautiful, blazing-fast screenshot & recording app for Mac.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            // Feature highlights
            VStack(alignment: .leading, spacing: 12) {
                FeatureHighlight(icon: "camera.viewfinder", text: "Capture area, fullscreen, or window screenshots")
                FeatureHighlight(icon: "record.circle", text: "Record screen with system audio & microphone")
                FeatureHighlight(icon: "pencil.and.outline", text: "Annotate and edit captures instantly")
            }
            .padding(.top, 8)

            Spacer()

            Button("Let's do it!") {
                withAnimation(.easeInOut(duration: 0.4)) { currentStep = 1 }
            }
            .buttonStyle(OnboardingPrimaryButton())
            .keyboardShortcut(.return, modifiers: [])

            Spacer().frame(height: 48)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Step 2: Grant Permissions (all on one page)

    private var permissionsStep: some View {
        VStack(spacing: 0) {
            Spacer()

            // Header
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.7))

            Text("Grant Permissions")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 20)

            Text("SnapForge needs permissions for capture, audio, and accessibility.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .padding(.top, 4)

            // Permission rows
            VStack(spacing: 12) {
                OnboardingPermissionRow(
                    icon: "rectangle.dashed.badge.record",
                    title: "Screen Recording",
                    description: "Required for screenshots and recordings",
                    isRequired: true,
                    isGranted: permissionService.screenRecordingStatus == .granted,
                    onGrant: { Task { await permissionService.requestScreenRecording() } }
                )

                OnboardingPermissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "Optional for voice recording",
                    isRequired: false,
                    isGranted: permissionService.microphoneStatus == .granted,
                    onGrant: { Task { await permissionService.requestMicrophone() } }
                )

                OnboardingPermissionRow(
                    icon: "camera.fill",
                    title: "Camera",
                    description: "Optional for webcam overlay",
                    isRequired: false,
                    isGranted: permissionService.cameraStatus == .granted,
                    onGrant: { Task { await permissionService.requestCamera() } }
                )

                OnboardingPermissionRow(
                    icon: "hand.raised.fill",
                    title: "Accessibility",
                    description: "Optional for keystroke display & shortcuts",
                    isRequired: false,
                    isGranted: permissionService.accessibilityStatus == .granted,
                    onGrant: { permissionService.requestAccessibility() }
                )
            }
            .frame(maxWidth: 420)
            .padding(.top, 24)

            Spacer()

            // Bottom navigation
            HStack(spacing: 16) {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(OnboardingSecondaryButton())

                Button("Next") {
                    withAnimation(.easeInOut(duration: 0.4)) { currentStep = 2 }
                }
                .buttonStyle(OnboardingPrimaryButton())
                .disabled(permissionService.screenRecordingStatus != .granted)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.bottom, 48)
        }
        .padding(.horizontal, 40)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionService.refreshAll()
        }
    }

    // MARK: - Step 3: Keyboard Shortcuts

    private var shortcutsStep: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "keyboard")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.7))

            Text("Keyboard Shortcuts")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 20)

            Text("Use these shortcuts for quick access to SnapForge.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .padding(.top, 4)

            // Shortcut groups
            VStack(spacing: 14) {
                ShortcutGroupCard(title: "CAPTURE", shortcuts: [
                    ("⌘⇧3", "Capture Fullscreen"),
                    ("⌘⇧4", "Capture Area"),
                    ("⌘⇧W", "Capture Window"),
                ])

                ShortcutGroupCard(title: "RECORDING", shortcuts: [
                    ("⌘⇧5", "Record Screen"),
                ])

                ShortcutGroupCard(title: "TOOLS", shortcuts: [
                    ("⌘⇧A", "Open Annotate"),
                ])
            }
            .frame(maxWidth: 380)
            .padding(.top, 20)

            // Hint text
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.3))
                Text("Customize shortcuts anytime in Preferences → Shortcuts.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.top, 12)

            Spacer()

            HStack(spacing: 16) {
                Button("Skip") {
                    withAnimation(.easeInOut(duration: 0.4)) { currentStep = 3 }
                }
                .buttonStyle(OnboardingSecondaryButton())

                Button("Next") {
                    withAnimation(.easeInOut(duration: 0.4)) { currentStep = 3 }
                }
                .buttonStyle(OnboardingPrimaryButton())
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.bottom, 48)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Step 4: Completion

    private var completionStep: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "checkmark.circle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.green.opacity(0.85))

            Text("You're all set!")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 20)

            Text("SnapForge is ready. Access it from the menu bar or use your keyboard shortcuts.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .padding(.top, 4)

            // Quick reference hint cards
            VStack(spacing: 10) {
                CompletionHintCard(
                    icon: "menubar.arrow.up.rectangle",
                    title: "Menu Bar",
                    description: "Look for the SnapForge icon in your menu bar"
                )
                CompletionHintCard(
                    icon: "keyboard",
                    title: "Shortcuts",
                    description: "Use ⌘⇧3, ⌘⇧4, ⌘⇧5 to capture anytime"
                )
                CompletionHintCard(
                    icon: "gearshape",
                    title: "Preferences",
                    description: "Customize shortcuts, output format, and more"
                )
            }
            .frame(maxWidth: 380)
            .padding(.top, 20)

            Spacer()

            // Actions
            VStack(spacing: 10) {
                HStack(spacing: 16) {
                    Button("Open Preferences") {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                        AppCoordinator.shared.dismissOnboarding()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))

                    Button("Get Started") {
                        AppCoordinator.shared.dismissOnboarding()
                    }
                    .buttonStyle(OnboardingSuccessButton())
                    .keyboardShortcut(.return, modifiers: [])
                }

                Text("Press Enter ↵")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(.bottom, 48)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Feature Highlight (Welcome Step)

private struct FeatureHighlight: View {
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

private struct OnboardingPermissionRow: View {
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

private struct ShortcutGroupCard: View {
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

private struct CompletionHintCard: View {
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

// MARK: - Button Styles

private struct OnboardingPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .padding(.horizontal, 20)
            .background(
                Capsule()
                    .fill(.white.opacity(0.18))
            )
            .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

private struct OnboardingSecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
            .padding(.vertical, 8)
            .padding(.horizontal, 20)
            .background(
                Capsule()
                    .fill(.white.opacity(0.08))
            )
            .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

private struct OnboardingSuccessButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .padding(.horizontal, 20)
            .background(
                Capsule()
                    .fill(Color.green.opacity(0.3))
            )
            .overlay(Capsule().stroke(.green.opacity(0.5), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}
