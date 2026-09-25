import SwiftUI

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
            return FireTheme.contrastPanelShadow
        case .chrome, .quiet:
            return FireTheme.panelShadow
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
