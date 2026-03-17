import SwiftUI

// MARK: - Button Styles

struct OnboardingPrimaryButton: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .padding(.horizontal, 20)
            .background(
                Capsule()
                    .fill(.white.opacity(isHovered ? 0.25 : 0.18))
            )
            .overlay { Capsule().stroke(.white.opacity(isHovered ? 0.4 : 0.25), lineWidth: 1) }
            .shadow(color: .white.opacity(isHovered ? 0.15 : 0), radius: 8, y: 0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}

struct OnboardingSecondaryButton: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white.opacity(isHovered ? 0.8 : 0.6))
            .padding(.vertical, 8)
            .padding(.horizontal, 20)
            .background(
                Capsule()
                    .fill(.white.opacity(isHovered ? 0.12 : 0.08))
            )
            .overlay { Capsule().stroke(.white.opacity(isHovered ? 0.25 : 0.15), lineWidth: 1) }
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}

struct OnboardingSuccessButton: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .padding(.horizontal, 20)
            .background(
                Capsule()
                    .fill(Color.green.opacity(isHovered ? 0.4 : 0.3))
            )
            .overlay { Capsule().stroke(.green.opacity(isHovered ? 0.7 : 0.5), lineWidth: 1) }
            .shadow(color: .green.opacity(isHovered ? 0.2 : 0), radius: 8, y: 0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}
