import SwiftUI
import UIKit

enum FireAppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    case oled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "跟随系统"
        case .light:
            return "浅色"
        case .dark:
            return "深色"
        case .oled:
            return "纯黑"
        }
    }

    /// Short label for the three-segment appearance control (Dark / System / Light).
    /// `.oled` is not a segment; it is normalized to dark in the picker UI.
    var shortTitle: String {
        switch self {
        case .system:
            return "系统"
        case .light:
            return "浅色"
        case .dark, .oled:
            return "深色"
        }
    }

    /// SF Symbol for the three-segment appearance control.
    var systemImage: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max"
        case .dark, .oled:
            return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark, .oled:
            return .dark
        }
    }
}

/// Design tokens for Fire.
///
/// Dark mode follows a pure-black canvas + elevated charcoal card language
/// (unified across the app, not limited to settings/profile). Light mode keeps
/// a warm paper canvas. UIKit prefers `ui*`; SwiftUI uses `Color` wrappers.
enum FireTheme {
    // MARK: - Accent (brand — orange / fire, not reference-app green)

    static let uiAccent = adaptiveUIColor(
        UIColor(red: 0.91, green: 0.39, blue: 0.18, alpha: 1),
        UIColor(red: 0.98, green: 0.48, blue: 0.24, alpha: 1)
    )
    static let uiAccentSoft = adaptiveUIColor(
        UIColor(red: 0.98, green: 0.65, blue: 0.40, alpha: 1),
        UIColor(red: 1.00, green: 0.62, blue: 0.40, alpha: 1)
    )
    static let uiAccentGlow = adaptiveUIColor(
        UIColor(red: 0.99, green: 0.82, blue: 0.68, alpha: 1),
        UIColor(red: 1.00, green: 0.72, blue: 0.52, alpha: 1)
    )

    static var accent: Color { Color(uiColor: uiAccent) }
    static var accentSoft: Color { Color(uiColor: uiAccentSoft) }
    static var accentGlow: Color { Color(uiColor: uiAccentGlow) }

    // MARK: - Semantic

    static let uiSuccess = adaptiveUIColor(
        UIColor(red: 0.25, green: 0.63, blue: 0.45, alpha: 1),
        UIColor(red: 0.38, green: 0.78, blue: 0.55, alpha: 1)
    )
    static let uiWarning = adaptiveUIColor(
        UIColor(red: 0.80, green: 0.49, blue: 0.20, alpha: 1),
        UIColor(red: 0.95, green: 0.62, blue: 0.30, alpha: 1)
    )
    static let uiError = adaptiveUIColor(
        UIColor(red: 0.90, green: 0.28, blue: 0.22, alpha: 1),
        UIColor(red: 1.00, green: 0.38, blue: 0.28, alpha: 1)
    )
    static let uiInfo = adaptiveUIColor(
        UIColor(red: 0.20, green: 0.48, blue: 0.96, alpha: 1),
        UIColor(red: 0.40, green: 0.62, blue: 1.00, alpha: 1)
    )

    static var success: Color { Color(uiColor: uiSuccess) }
    static var warning: Color { Color(uiColor: uiWarning) }

    // MARK: - Canvas (page background)
    // Dark: pure black. OLED: pure black. Light: warm paper.

    private static let darkCanvas = UIColor.black
    private static let darkCard = UIColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1) // ~#1C1C1E
    private static let darkCardElevated = UIColor(red: 0.173, green: 0.173, blue: 0.180, alpha: 1) // ~#2C2C2E
    private static let darkIconWell = UIColor(red: 0.070, green: 0.070, blue: 0.075, alpha: 1)
    private static let darkChrome = UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 0.92)

    static let uiCanvasTop = adaptiveUIColor(
        UIColor(red: 0.96, green: 0.95, blue: 0.93, alpha: 1),
        darkCanvas,
        oled: UIColor.black
    )
    static let uiCanvasMid = adaptiveUIColor(
        UIColor(red: 0.95, green: 0.94, blue: 0.92, alpha: 1),
        darkCanvas,
        oled: UIColor.black
    )
    static let uiCanvasBottom = adaptiveUIColor(
        UIColor(red: 0.93, green: 0.92, blue: 0.91, alpha: 1),
        darkCanvas,
        oled: UIColor.black
    )

    static var canvasTop: Color { Color(uiColor: uiCanvasTop) }
    static var canvasMid: Color { Color(uiColor: uiCanvasMid) }
    static var canvasBottom: Color { Color(uiColor: uiCanvasBottom) }

    // MARK: - Surfaces (cards / rows)

    static var uiCanvas: UIColor { uiCanvasMid }

    /// Primary floating card (settings groups, profile blocks).
    static let uiSurface = adaptiveUIColor(
        UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1),
        darkCard,
        oled: darkCard
    )
    /// Nested / secondary fill inside a card.
    static let uiSurfaceSecondary = adaptiveUIColor(
        UIColor(red: 0.95, green: 0.94, blue: 0.93, alpha: 1),
        darkCardElevated,
        oled: darkCardElevated
    )
    static let uiPanel = adaptiveUIColor(
        UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1),
        darkCard,
        oled: darkCard
    )
    static let uiPanelElevated = adaptiveUIColor(
        UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1),
        darkCardElevated,
        oled: darkCardElevated
    )
    /// Icon well behind SF Symbols in list rows.
    static let uiIconWell = adaptiveUIColor(
        UIColor(red: 0.94, green: 0.93, blue: 0.92, alpha: 1),
        darkIconWell,
        oled: UIColor(white: 0.05, alpha: 1)
    )
    /// Navigation / status chrome. Light mode stays close to page canvas so the top bar
    /// does not read as a separate cooler-white container above warm paper content.
    static let uiChrome = adaptiveUIColor(
        UIColor(red: 0.95, green: 0.94, blue: 0.92, alpha: 0.94),
        darkChrome,
        oled: UIColor(white: 0.0, alpha: 0.92)
    )
    static let uiChromeStrong = adaptiveUIColor(
        UIColor(red: 0.95, green: 0.94, blue: 0.92, alpha: 0.98),
        UIColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 0.96),
        oled: UIColor(white: 0.06, alpha: 0.96)
    )
    static let uiSoftSurface = adaptiveUIColor(
        UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.56),
        UIColor(white: 1, alpha: 0.06)
    )
    static let uiTrack = adaptiveUIColor(
        UIColor(red: 0.92, green: 0.91, blue: 0.90, alpha: 1),
        UIColor(white: 1, alpha: 0.10)
    )

    static var surface: Color { Color(uiColor: uiSurface) }
    static var surfaceSecondary: Color { Color(uiColor: uiSurfaceSecondary) }
    static var panel: Color { Color(uiColor: uiPanel) }
    static var panelElevated: Color { Color(uiColor: uiPanelElevated) }
    static var chrome: Color { Color(uiColor: uiChrome) }
    static var chromeStrong: Color { Color(uiColor: uiChromeStrong) }
    static var softSurface: Color { Color(uiColor: uiSoftSurface) }
    static var track: Color { Color(uiColor: uiTrack) }

    // MARK: - Text

    static let uiInk = adaptiveUIColor(
        UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1),
        UIColor(white: 1.0, alpha: 0.96)
    )
    static let uiSubtleInk = adaptiveUIColor(
        UIColor(red: 0.40, green: 0.40, blue: 0.43, alpha: 1),
        UIColor(white: 1.0, alpha: 0.55)
    )
    static let uiTertiaryInk = adaptiveUIColor(
        UIColor(red: 0.55, green: 0.55, blue: 0.58, alpha: 1),
        UIColor(white: 1.0, alpha: 0.38)
    )
    static let uiInverseInk = adaptiveUIColor(
        UIColor(red: 0.98, green: 0.96, blue: 0.93, alpha: 1),
        UIColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1)
    )
    static let uiInverseSubtleInk = adaptiveUIColor(
        UIColor(red: 0.78, green: 0.74, blue: 0.69, alpha: 1),
        UIColor(red: 0.40, green: 0.40, blue: 0.42, alpha: 1)
    )

    static var ink: Color { Color(uiColor: uiInk) }
    static var subtleInk: Color { Color(uiColor: uiSubtleInk) }
    static var tertiaryInk: Color { Color(uiColor: uiTertiaryInk) }
    static var inverseInk: Color { Color(uiColor: uiInverseInk) }
    static var inverseSubtleInk: Color { Color(uiColor: uiInverseSubtleInk) }

    // MARK: - Borders & Dividers

    static let uiDivider = adaptiveUIColor(
        UIColor(white: 0, alpha: 0.08),
        UIColor(white: 1, alpha: 0.08)
    )
    static let uiChromeBorder = adaptiveUIColor(
        UIColor(white: 1, alpha: 0.40),
        UIColor(white: 1, alpha: 0.08)
    )
    static let uiInverseDivider = adaptiveUIColor(
        UIColor(white: 1, alpha: 0.10),
        UIColor(white: 1, alpha: 0.10)
    )
    static let uiThreadLine = adaptiveUIColor(
        UIColor(white: 0, alpha: 0.10),
        UIColor(white: 1, alpha: 0.08)
    )
    static let uiPanelShadow = adaptiveUIColor(
        UIColor(white: 0, alpha: 0.06),
        UIColor(white: 0, alpha: 0.40)
    )
    static let uiContrastPanelShadow = adaptiveUIColor(
        UIColor(white: 0, alpha: 0.14),
        UIColor(white: 0, alpha: 0.55)
    )

    static var divider: Color { Color(uiColor: uiDivider) }
    static var chromeBorder: Color { Color(uiColor: uiChromeBorder) }
    static var inverseDivider: Color { Color(uiColor: uiInverseDivider) }
    static var threadLine: Color { Color(uiColor: uiThreadLine) }
    static var panelShadow: Color { Color(uiColor: uiPanelShadow) }
    static var contrastPanelShadow: Color { Color(uiColor: uiContrastPanelShadow) }

    // MARK: - Chips

    static let uiTagChipBackground = adaptiveUIColor(
        UIColor(red: 0.46, green: 0.46, blue: 0.50, alpha: 0.08),
        UIColor(white: 1, alpha: 0.08)
    )
    static let uiTagChipForeground = adaptiveUIColor(
        UIColor(red: 0.30, green: 0.30, blue: 0.33, alpha: 1),
        UIColor(white: 1, alpha: 0.72)
    )

    static var tagChipBackground: Color { Color(uiColor: uiTagChipBackground) }
    static var tagChipForeground: Color { Color(uiColor: uiTagChipForeground) }

    static func categoryChipBackground(accent: Color, isDark: Bool) -> Color {
        accent.opacity(isDark ? 0.22 : 0.14)
    }

    static func uiCategoryChipBackground(accent: UIColor) -> UIColor {
        UIColor { traits in
            let resolvedAccent = accent.resolvedColor(with: traits)
            let alpha: CGFloat = traits.userInterfaceStyle == .dark ? 0.22 : 0.14
            return resolvedAccent.withAlphaComponent(alpha)
        }
    }

    // MARK: - Skeleton

    static let uiSkeletonBase = adaptiveUIColor(
        UIColor(white: 0.90, alpha: 1),
        UIColor(white: 0.16, alpha: 1),
        oled: UIColor(white: 0.12, alpha: 1)
    )
    static let uiSkeletonHighlight = adaptiveUIColor(
        UIColor(white: 0.96, alpha: 1),
        UIColor(white: 0.26, alpha: 1),
        oled: UIColor(white: 0.20, alpha: 1)
    )

    // MARK: - Tab Bar

    static let uiTabBarBackground = adaptiveUIColor(
        UIColor(red: 0.95, green: 0.94, blue: 0.92, alpha: 0.96),
        UIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 0.94),
        oled: UIColor(white: 0, alpha: 0.94)
    )

    static var tabBarBackground: Color { Color(uiColor: uiTabBarBackground) }

    // MARK: - Helpers

    static var isOledMode: Bool {
        FireAppearancePreference(
            rawValue: UserDefaults.standard.string(forKey: appearancePreferenceStorageKey) ?? ""
        ) == .oled
    }

    static let appearancePreferenceStorageKey = "fire.appearancePreference"

    static func adaptiveUIColor(_ light: UIColor, _ dark: UIColor, oled: UIColor? = nil) -> UIColor {
        UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return isOledMode ? (oled ?? dark) : dark
            }
            return light
        }
    }

    /// Apply global UIKit chrome defaults (nav/tab/table) to match the design language.
    @MainActor
    static func applyGlobalAppearances() {
        let nav = UINavigationBarAppearance()
        nav.configureWithDefaultBackground()
        nav.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        nav.backgroundColor = uiChrome
        nav.shadowColor = uiDivider
        nav.titleTextAttributes = [.foregroundColor: uiInk]
        nav.largeTitleTextAttributes = [.foregroundColor: uiInk]

        let navBar = UINavigationBar.appearance()
        navBar.standardAppearance = nav
        navBar.scrollEdgeAppearance = nav
        navBar.compactAppearance = nav
        navBar.tintColor = uiAccent

        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        tab.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        tab.backgroundColor = uiTabBarBackground
        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = tab
        tabBar.scrollEdgeAppearance = tab
        tabBar.tintColor = uiAccent
        tabBar.unselectedItemTintColor = uiTertiaryInk

        UITableView.appearance().backgroundColor = uiCanvas
        UICollectionView.appearance().backgroundColor = uiCanvas
    }
}

// MARK: - Layout constants (unified design language)

extension FireTheme {
    /// Large floating cards (settings groups, profile blocks).
    static let cornerRadius: CGFloat = 22
    /// Medium cards / chips containers.
    static let mediumCornerRadius: CGFloat = 16
    /// Small controls, inputs.
    static let smallCornerRadius: CGFloat = 12
    /// Icon wells behind list-row symbols.
    static let iconWellCornerRadius: CGFloat = 10
    static let iconWellSize: CGFloat = 36
    static let chipCornerRadius: CGFloat = 100
    static let panelShadowRadius: CGFloat = 16
    static let panelShadowY: CGFloat = 8
    /// Horizontal inset for page content / cards.
    static let pageHorizontalInset: CGFloat = 16
    /// Vertical gap between grouped cards.
    static let sectionSpacing: CGFloat = 22
}
