import SwiftUI
import AppKit

/// Full-screen countdown overlay for Self-Timer Capture.
/// Shows the selected area with a thin border, dimmed surroundings, and a compact
/// countdown badge at the top-center of the selection.
/// Hover over the badge to reveal Cancel; click to dismiss.
struct CountdownOverlayView: View {
    let totalSeconds: Int
    let captureRect: CGRect  // In screen (AppKit) coordinates
    let screenSize: CGSize
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var remaining: Int
    @State private var pulseScale: CGFloat = 1.0
    @State private var isHovering = false

    init(
        totalSeconds: Int = 5,
        captureRect: CGRect = .zero,
        screenSize: CGSize = .zero,
        onComplete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.totalSeconds = totalSeconds
        self.captureRect = captureRect
        self.screenSize = screenSize
        self.onComplete = onComplete
        self.onCancel = onCancel
        self._remaining = State(initialValue: totalSeconds)
    }

    /// The captureRect is already in CG screen coordinates (Y=0 at top),
    /// which matches SwiftUI's coordinate space — no conversion needed.
    private var displayRect: CGRect { captureRect }

    var body: some View {
        ZStack {
            // Dimmed background with cutout for the selected area
            Canvas { context, size in
                // Fill entire screen with dim color
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .color(.black.opacity(0.45))
                )
                // Cut out the selected area (clear)
                context.blendMode = .clear
                context.fill(
                    Path(displayRect),
                    with: .color(.white)
                )
            }
            .ignoresSafeArea()

            // Thin white border around selected area
            Rectangle()
                .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                .frame(width: displayRect.width, height: displayRect.height)
                .position(
                    x: displayRect.midX,
                    y: displayRect.midY
                )

            // Countdown badge — centered above the selected area
            countdownBadge
                .position(
                    x: displayRect.midX,
                    y: max(displayRect.minY - 30, 30) // 30pt above selection, clamped
                )
        }
        .task {
            // Play initial tick sound
            playCountdownSound()

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch { return } // Task was cancelled during sleep
                guard !Task.isCancelled else { return }
                if remaining > 1 {
                    remaining -= 1
                    playCountdownSound()
                    // Pulse animation
                    withAnimation(.easeOut(duration: 0.25)) {
                        pulseScale = 1.2
                    }
                    withAnimation(.easeInOut(duration: 0.2).delay(0.25)) {
                        pulseScale = 1.0
                    }
                } else {
                    // Play final "go" sound if countdown sound is enabled
                    if UserDefaults.standard.bool(forKey: SettingsKey.countdownSoundEnabled) {
                        NSSound(named: "Pop")?.play()
                    }
                    onComplete()
                    return
                }
            }
        }
    }

    // MARK: - Sound

    /// Play tick sound if countdown sound is enabled in settings
    private func playCountdownSound() {
        guard UserDefaults.standard.bool(forKey: SettingsKey.countdownSoundEnabled) else { return }
        NSSound(named: "Tink")?.play()
    }

    // MARK: - Countdown Badge

    private var countdownBadge: some View {
        Button(action: onCancel) {
            HStack(spacing: 6) {
                if isHovering {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Cancel")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                } else {
                    Image(systemName: "timer")
                        .font(.system(size: 14, weight: .semibold))
                    Text("\(remaining)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isHovering ? Color.red : Color.orange)
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
            )
            .scaleEffect(pulseScale)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}
