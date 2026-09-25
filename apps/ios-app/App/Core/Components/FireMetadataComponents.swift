import SwiftUI

// MARK: - Section Lead

struct FireSectionLead: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var inverse = false

    private var eyebrowColor: Color {
        inverse ? FireTheme.inverseSubtleInk : FireTheme.tertiaryInk
    }

    private var titleColor: Color {
        inverse ? FireTheme.inverseInk : FireTheme.ink
    }

    private var subtitleColor: Color {
        inverse ? FireTheme.inverseSubtleInk : FireTheme.subtleInk
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(.caption.weight(.semibold))
                .tracking(1.6)
                .foregroundStyle(eyebrowColor)

            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(titleColor)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(subtitleColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Status Chip

struct FireStatusChip: View {
    let label: String
    let tone: Tone
    var inverse = false

    enum Tone {
        case accent
        case success
        case warning
        case muted
    }

    private var background: Color {
        switch tone {
        case .accent:
            return FireTheme.accent.opacity(inverse ? 0.2 : 0.12)
        case .success:
            return FireTheme.success.opacity(inverse ? 0.2 : 0.12)
        case .warning:
            return FireTheme.warning.opacity(inverse ? 0.18 : 0.12)
        case .muted:
            return inverse ? FireTheme.inverseDivider : FireTheme.softSurface
        }
    }

    private var foreground: Color {
        switch tone {
        case .accent:
            return inverse ? FireTheme.accentGlow : FireTheme.accent
        case .success:
            return FireTheme.success
        case .warning:
            return FireTheme.warning
        case .muted:
            return inverse ? FireTheme.inverseSubtleInk : FireTheme.subtleInk
        }
    }

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(Capsule())
    }
}

// MARK: - Topic Pill

struct FireTopicPill: View {
    let label: String
    let backgroundColor: Color
    let foregroundColor: Color

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
    }
}

// MARK: - Inline Meta

struct FireInlineMeta: View {
    let label: String
    let symbol: String
    var color: Color = FireTheme.tertiaryInk

    var body: some View {
        Label(label, systemImage: symbol)
            .font(.caption2)
            .foregroundStyle(color)
    }
}

// MARK: - Metric Tile

struct FireMetricTile: View {
    let label: String
    let value: String
    var inverse = false

    private var backgroundColor: Color {
        inverse ? FireTheme.inverseDivider : FireTheme.softSurface
    }

    private var valueColor: Color {
        inverse ? FireTheme.inverseInk : FireTheme.ink
    }

    private var labelColor: Color {
        inverse ? FireTheme.inverseSubtleInk : FireTheme.tertiaryInk
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(valueColor)
                .fireNumericChange(value: value)

            Text(label)
                .font(.caption)
                .foregroundStyle(labelColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: FireTheme.mediumCornerRadius, style: .continuous)
                .fill(backgroundColor)
        )
    }
}

// MARK: - Key Value Row

struct FireKeyValueRow: View {
    let label: String
    let value: String
    var inverse = false

    private var labelColor: Color {
        inverse ? FireTheme.inverseSubtleInk : FireTheme.subtleInk
    }

    private var valueColor: Color {
        inverse ? FireTheme.inverseInk : FireTheme.ink
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(labelColor)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 12)
    }
}
