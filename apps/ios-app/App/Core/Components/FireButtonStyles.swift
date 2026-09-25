import SwiftUI

// MARK: - Toolbar Icon

struct FireToolbarIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(FireTheme.subtleInk)
            .frame(width: 36, height: 36)
            .background(
                Circle()
                    .fill(FireTheme.softSurface)
                    .overlay(
                        Circle()
                            .strokeBorder(FireTheme.divider, lineWidth: 1)
                    )
            )
    }
}

// MARK: - Button Styles

struct FirePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [FireTheme.accent, FireTheme.accentSoft],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.92 : 1) : 0.55)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(
                .spring(response: 0.28, dampingFraction: 0.55),
                value: configuration.isPressed
            )
            .animation(.easeOut(duration: 0.15), value: isEnabled)
    }
}

struct FireSecondaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(FireTheme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(FireTheme.softSurface)
                    .overlay(
                        Capsule()
                            .strokeBorder(FireTheme.divider, lineWidth: 1)
                    )
            )
            .opacity(configuration.isPressed ? 0.92 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(
                .spring(response: 0.28, dampingFraction: 0.55),
                value: configuration.isPressed
            )
    }
}
