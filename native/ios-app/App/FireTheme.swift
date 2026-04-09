import SwiftUI
import UIKit

enum FireTheme {
    // MARK: - Accent

    static let accent = adaptive(
        UIColor(red: 0.91, green: 0.39, blue: 0.18, alpha: 1),
        UIColor(red: 0.96, green: 0.45, blue: 0.22, alpha: 1)
    )
    static let accentSoft = adaptive(
        UIColor(red: 0.98, green: 0.65, blue: 0.40, alpha: 1),
        UIColor(red: 1.00, green: 0.73, blue: 0.50, alpha: 1)
    )
    static let accentGlow = adaptive(
        UIColor(red: 0.99, green: 0.82, blue: 0.68, alpha: 1),
        UIColor(red: 1.00, green: 0.79, blue: 0.62, alpha: 1)
    )

    // MARK: - Semantic

    static let success = adaptive(
        UIColor(red: 0.25, green: 0.63, blue: 0.45, alpha: 1),
        UIColor(red: 0.38, green: 0.76, blue: 0.55, alpha: 1)
    )
    static let warning = adaptive(
        UIColor(red: 0.80, green: 0.49, blue: 0.20, alpha: 1),
        UIColor(red: 0.93, green: 0.60, blue: 0.29, alpha: 1)
    )

    // MARK: - Canvas

    static let canvasTop = adaptive(
        UIColor(red: 0.96, green: 0.95, blue: 0.93, alpha: 1),
        UIColor(red: 0.08, green: 0.09, blue: 0.10, alpha: 1)
    )
    static let canvasMid = adaptive(
        UIColor(red: 0.94, green: 0.93, blue: 0.91, alpha: 1),
        UIColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1)
    )
    static let canvasBottom = adaptive(
        UIColor(red: 0.92, green: 0.92, blue: 0.91, alpha: 1),
        UIColor(red: 0.13, green: 0.14, blue: 0.17, alpha: 1)
    )

    // MARK: - Surfaces

    static let panel = adaptive(
        UIColor(red: 0.14, green: 0.13, blue: 0.13, alpha: 1),
        UIColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1)
    )
    static let panelElevated = adaptive(
        UIColor(red: 0.20, green: 0.18, blue: 0.17, alpha: 1),
        UIColor(red: 0.17, green: 0.17, blue: 0.19, alpha: 1)
    )
    static let chrome = adaptive(
        UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.78),
        UIColor(red: 0.16, green: 0.17, blue: 0.19, alpha: 0.90)
    )
    static let chromeStrong = adaptive(
        UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.92),
        UIColor(red: 0.19, green: 0.20, blue: 0.22, alpha: 0.96)
    )
    static let softSurface = adaptive(
        UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.56),
        UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.06)
    )
    static let track = adaptive(
        UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.52),
        UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.08)
    )

    // MARK: - Text

    static let ink = adaptive(
        UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1),
        UIColor(red: 0.96, green: 0.95, blue: 0.93, alpha: 1)
    )
    static let subtleInk = adaptive(
        UIColor(red: 0.35, green: 0.35, blue: 0.38, alpha: 1),
        UIColor(red: 0.79, green: 0.78, blue: 0.75, alpha: 1)
    )
    static let tertiaryInk = adaptive(
        UIColor(red: 0.52, green: 0.52, blue: 0.55, alpha: 1),
        UIColor(red: 0.62, green: 0.63, blue: 0.67, alpha: 1)
    )
    static let inverseInk = adaptive(
        UIColor(red: 0.98, green: 0.96, blue: 0.93, alpha: 1),
        UIColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1)
    )
    static let inverseSubtleInk = adaptive(
        UIColor(red: 0.78, green: 0.74, blue: 0.69, alpha: 1),
        UIColor(red: 0.73, green: 0.73, blue: 0.76, alpha: 1)
    )

    // MARK: - Borders & Dividers

    static let divider = adaptive(
        UIColor(white: 0, alpha: 0.08),
        UIColor(white: 1, alpha: 0.08)
    )
    static let chromeBorder = adaptive(
        UIColor(white: 1, alpha: 0.40),
        UIColor(white: 1, alpha: 0.10)
    )
    static let inverseDivider = adaptive(
        UIColor(white: 1, alpha: 0.10),
        UIColor(white: 1, alpha: 0.10)
    )
    static let threadLine = adaptive(
        UIColor(white: 0, alpha: 0.10),
        UIColor(white: 1, alpha: 0.10)
    )

    // MARK: - Chips

    static let tagChipBackground = adaptive(
        UIColor(red: 0.46, green: 0.46, blue: 0.50, alpha: 0.08),
        UIColor(white: 1, alpha: 0.10)
    )
    static let tagChipForeground = adaptive(
        UIColor(red: 0.30, green: 0.30, blue: 0.33, alpha: 1),
        UIColor(red: 0.85, green: 0.84, blue: 0.82, alpha: 1)
    )

    static func categoryChipBackground(accent: Color, isDark: Bool) -> Color {
        accent.opacity(isDark ? 0.22 : 0.14)
    }

    // MARK: - Tab Bar

    static let tabBarBackground = adaptive(
        UIColor(red: 0.97, green: 0.96, blue: 0.95, alpha: 0.94),
        UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 0.94)
    )

    // MARK: - Helpers

    private static func adaptive(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(
            uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light
            }
        )
    }
}

// MARK: - Constants

extension FireTheme {
    static let cornerRadius: CGFloat = 20
    static let smallCornerRadius: CGFloat = 14
    static let chipCornerRadius: CGFloat = 100
    static let panelShadowRadius: CGFloat = 16
    static let panelShadowY: CGFloat = 8
}
