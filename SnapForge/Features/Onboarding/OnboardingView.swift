import SwiftUI
import AVFoundation

// MARK: - Onboarding Flow (4 steps)

struct OnboardingView: View {
    @State private var currentStep = 0
    @State private var permissionService = AppEnvironment.shared.permissionService

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
        .frame(width: 640, height: 620)
        .preferredColorScheme(.dark)
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 32)

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
                .frame(maxWidth: 400)

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
            .focusEffectDisabled()

            Spacer().frame(height: 56)
        }
        .padding(.horizontal, 48)
    }

    // MARK: - Step 2: Grant Permissions (all on one page)

    private var permissionsStep: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 32)

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
                .frame(maxWidth: 400)
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
            .frame(maxWidth: 500)
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
                .focusEffectDisabled()
            }
            .padding(.bottom, 48)
        }
        .padding(.horizontal, 48)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionService.refreshAll()
        }
    }

    // MARK: - Step 3: Keyboard Shortcuts

    private var shortcutsStep: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 32)

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
                .frame(maxWidth: 400)
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
                Text("Customize shortcuts anytime in Settings → Shortcuts.")
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
                .focusEffectDisabled()
            }
            .padding(.bottom, 48)
        }
        .padding(.horizontal, 48)
    }

    // MARK: - Step 4: Completion

    private var completionStep: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 32)

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
                .frame(maxWidth: 400)
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
                    title: "Settings",
                    description: "Customize shortcuts, output format, and more"
                )
            }
            .frame(maxWidth: 460)
            .padding(.top, 20)

            Spacer()

            // Actions
            VStack(spacing: 10) {
                HStack(spacing: 16) {
                    SettingsLink {
                        Text("Open Settings")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))

                    Button("Get Started") {
                        AppCoordinator.shared.dismissOnboarding()
                    }
                    .buttonStyle(OnboardingSuccessButton())
                    .keyboardShortcut(.return, modifiers: [])
                    .focusEffectDisabled()
                }

                Text("Press Enter ↵")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(.bottom, 48)
        }
        .padding(.horizontal, 48)
    }
}
