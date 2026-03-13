import SwiftUI

/// Full-screen countdown overlay for Self-Timer Capture.
/// Shows a large animated number counting down, then triggers capture.
struct CountdownOverlayView: View {
    let totalSeconds: Int
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var remaining: Int
    @State private var animateScale = false
    @State private var countdownTask: Task<Void, Never>?

    init(totalSeconds: Int = 5, onComplete: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.totalSeconds = totalSeconds
        self.onComplete = onComplete
        self.onCancel = onCancel
        self._remaining = State(initialValue: totalSeconds)
    }

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Countdown number
                Text("\(remaining)")
                    .font(.system(size: 160, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 20)
                    .scaleEffect(animateScale ? 1.0 : 1.4)
                    .opacity(animateScale ? 1.0 : 0.3)
                    .animation(.easeOut(duration: 0.4), value: animateScale)
                    .id(remaining) // Force view reload on change

                // Label
                Text("Capturing in \(remaining)s...")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))

                // Progress ring
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.2), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: remaining)
                }
                .frame(width: 60, height: 60)

                // Cancel hint
                Text("Press Esc to cancel")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 8)
            }
        }
        .task {
            animateScale = true
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                if remaining > 1 {
                    remaining -= 1
                    animateScale = false
                    withAnimation {
                        animateScale = true
                    }
                } else {
                    onComplete()
                    return
                }
            }
        }
    }

    private var progress: CGFloat {
        CGFloat(remaining) / CGFloat(totalSeconds)
    }
}
