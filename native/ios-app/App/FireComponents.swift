import SwiftUI

// MARK: - Scene Background

struct FireSceneBackground: View {
    var body: some View {
        LinearGradient(
            colors: [FireTheme.canvasTop, FireTheme.canvasMid, FireTheme.canvasBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(FireTheme.accent.opacity(0.12))
                .frame(width: 260, height: 260)
                .blur(radius: 54)
                .offset(x: -80, y: -90)
        }
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(FireTheme.accentSoft.opacity(0.08))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: 90, y: 80)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Panel

enum FirePanelStyle {
    case contrast
    case chrome
    case quiet
}

struct FirePanel<Content: View>: View {
    let style: FirePanelStyle
    let padding: CGFloat
    @ViewBuilder let content: Content

    init(
        style: FirePanelStyle,
        padding: CGFloat = 20,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.padding = padding
        self.content = content()
    }

    private var fillStyle: AnyShapeStyle {
        switch style {
        case .contrast:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [FireTheme.panel, FireTheme.panelElevated],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .chrome:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [FireTheme.chromeStrong, FireTheme.chrome],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .quiet:
            return AnyShapeStyle(FireTheme.softSurface)
        }
    }

    private var borderColor: Color {
        switch style {
        case .contrast:
            return FireTheme.inverseDivider
        case .chrome:
            return FireTheme.chromeBorder
        case .quiet:
            return FireTheme.divider
        }
    }

    private var shadowColor: Color {
        switch style {
        case .contrast:
            return Color.black.opacity(0.14)
        case .chrome, .quiet:
            return Color.black.opacity(0.06)
        }
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: FireTheme.cornerRadius, style: .continuous)
                    .fill(fillStyle)
                    .overlay(
                        RoundedRectangle(cornerRadius: FireTheme.cornerRadius, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 1)
                    )
            )
            .shadow(color: shadowColor, radius: FireTheme.panelShadowRadius, y: FireTheme.panelShadowY)
    }
}

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
                .contentTransition(.numericText())

            Text(label)
                .font(.caption)
                .foregroundStyle(labelColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: FireTheme.smallCornerRadius, style: .continuous)
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

// MARK: - Error Banner

struct FireErrorBanner: View {
    let message: String
    let copied: Bool
    let onCopy: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(FireTheme.warning)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("Error")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FireTheme.ink)

                Text(message)
                    .font(.footnote.monospaced())
                    .foregroundStyle(FireTheme.subtleInk)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button {
                    onCopy()
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(FireTheme.subtleInk)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: FireTheme.smallCornerRadius, style: .continuous)
                .fill(FireTheme.softSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: FireTheme.smallCornerRadius, style: .continuous)
                        .strokeBorder(FireTheme.warning.opacity(0.28), lineWidth: 1)
                )
        )
    }
}

// MARK: - Empty Feed State

struct FireEmptyFeedState: View {
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.title2)
                .foregroundStyle(FireTheme.accent)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(FireTheme.subtleInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(actionTitle, action: action)
                .buttonStyle(FireSecondaryButtonStyle())
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Skeleton List

struct FireTopicSkeletonList: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { index in
                HStack(spacing: 12) {
                    Circle()
                        .fill(FireTheme.track)
                        .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(FireTheme.chromeStrong)
                            .frame(height: 14)

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(FireTheme.track)
                            .frame(width: 120, height: 10)
                    }

                    Spacer()

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(FireTheme.track)
                        .frame(width: 28, height: 20)
                }
                .padding(.vertical, 12)
                .redacted(reason: .placeholder)

                if index != 5 {
                    Divider()
                        .overlay(FireTheme.divider)
                }
            }
        }
    }
}

// MARK: - Feed Kind Selector

struct FireFeedKindSelector: View {
    let selectedKind: TopicListKindState
    let namespace: Namespace.ID
    let onSelect: (TopicListKindState) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(TopicListKindState.orderedCases, id: \.self) { kind in
                    Button {
                        onSelect(kind)
                    } label: {
                        ZStack {
                            if selectedKind == kind {
                                Capsule()
                                    .fill(FireTheme.panel)
                                    .matchedGeometryEffect(id: "feed-selection", in: namespace)
                            } else {
                                Capsule()
                                    .fill(Color.clear)
                            }

                            Text(kind.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(selectedKind == kind ? FireTheme.inverseInk : FireTheme.subtleInk)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(
                Capsule()
                    .fill(FireTheme.track)
            )
        }
        .scrollIndicators(.hidden)
    }
}

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
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct FireSecondaryButtonStyle: ButtonStyle {
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
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth > 0, lineWidth + spacing + size.width > maxWidth {
                totalHeight += lineHeight + spacing
                maxLineWidth = max(maxLineWidth, lineWidth)
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth += (lineWidth > 0 ? spacing : 0) + size.width
                lineHeight = max(lineHeight, size.height)
            }
        }

        totalHeight += lineHeight
        maxLineWidth = max(maxLineWidth, lineWidth)

        return CGSize(width: maxLineWidth, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var cursor = CGPoint(x: bounds.minX, y: bounds.minY)
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursor.x > bounds.minX, cursor.x + size.width > bounds.maxX {
                cursor.x = bounds.minX
                cursor.y += lineHeight + spacing
                lineHeight = 0
            }

            subview.place(
                at: cursor,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            cursor.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Avatar View

struct FireAvatarView: View {
    let avatarTemplate: String?
    let username: String
    let size: CGFloat
    var baseURLString: String = "https://linux.do"

    private var avatarURL: URL? {
        guard let avatarTemplate, !avatarTemplate.isEmpty else {
            return nil
        }
        let pixelSize = Int(size * UIScreen.main.scale)
        let path = avatarTemplate.replacingOccurrences(of: "{size}", with: "\(pixelSize)")
        if path.hasPrefix("http") {
            return URL(string: path)
        }
        if path.hasPrefix("//") {
            let scheme = URL(string: baseURLString)?.scheme ?? "https"
            return URL(string: "\(scheme):\(path)")
        }
        return URL(string: path, relativeTo: URL(string: baseURLString))?.absoluteURL
    }

    private var monogram: String {
        FireTopicPresentation.monogram(for: username.isEmpty ? "?" : username)
    }

    var body: some View {
        if let avatarURL {
            AsyncImage(url: avatarURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    monogramView
                default:
                    monogramView
                        .opacity(0.6)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            monogramView
        }
    }

    private var monogramView: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [FireTheme.accent, FireTheme.accentSoft],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(monogram)
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - String Extension

extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
