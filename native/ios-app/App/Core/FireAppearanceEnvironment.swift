import AsyncDisplayKit
import UIKit

// MARK: - Snapshot

/// Immutable, **resolved** palette for Texture / async display paths.
///
/// UIKit views may keep using dynamic `FireTheme.ui*` colors. Texture nodes must
/// only paint colors from a snapshot so display-queue trait environments cannot
/// freeze pure-black dark canvas fills after a light switch.
struct FireAppearanceSnapshot: Equatable {
    /// Stable identity for soft rebind early-outs (`light` / `dark` / `oled`).
    let token: String
    let userInterfaceStyle: UIUserInterfaceStyle
    let canvas: UIColor
    let surface: UIColor
    let ink: UIColor
    let subtleInk: UIColor
    let tertiaryInk: UIColor
    let accent: UIColor
    let divider: UIColor

    /// Traits used to build this snapshot (style-coherent; may include content size).
    let traits: UITraitCollection

    static func make(
        traits: UITraitCollection,
        preference: FireAppearancePreference = FireAppearanceEnvironment.currentPreference
    ) -> FireAppearanceSnapshot {
        let style = traits.userInterfaceStyle
        let token: String
        if style == .dark, preference == .oled {
            token = "oled"
        } else {
            token = FireTextureAttributedText.appearanceToken(for: traits)
        }
        return FireAppearanceSnapshot(
            token: token,
            userInterfaceStyle: style,
            canvas: FireTheme.uiCanvas.resolvedColor(with: traits),
            surface: FireTheme.uiSurface.resolvedColor(with: traits),
            ink: FireTheme.uiInk.resolvedColor(with: traits),
            subtleInk: FireTheme.uiSubtleInk.resolvedColor(with: traits),
            tertiaryInk: FireTheme.uiTertiaryInk.resolvedColor(with: traits),
            accent: FireTheme.uiAccent.resolvedColor(with: traits),
            divider: FireTheme.uiDivider.resolvedColor(with: traits),
            traits: traits
        )
    }

    func resolvingDynamicColors(_ attributed: NSAttributedString) -> NSAttributedString {
        FireTextureAttributedText.resolvingDynamicColors(attributed, with: traits)
    }
}

// MARK: - Environment

/// Single source of truth for app appearance preference → window override →
/// Texture-safe snapshots. Phase 0: helpers + trait resolution; preference
/// ownership still coexists with Settings / RootCoordinator writers.
///
/// Preference + UserDefaults reads are thread-safe. Window/view trait helpers
/// must be called from the main actor (UIKit).
enum FireAppearanceEnvironment {
    static var currentPreference: FireAppearancePreference {
        FireAppearancePreference(
            rawValue: UserDefaults.standard.string(forKey: FireTheme.appearancePreferenceStorageKey) ?? ""
        ) ?? .system
    }

    /// Style-coherent traits for baking. Prefer a loaded view; when the window
    /// override has already flipped but the view lag one run loop, force the
    /// override style so Texture never re-bakes the previous pure-black canvas.
    @MainActor
    static func traits(
        for view: UIView? = nil,
        window: UIWindow? = nil,
        fallback: UITraitCollection = .current
    ) -> UITraitCollection {
        let base: UITraitCollection
        if let view {
            base = view.traitCollection
        } else {
            base = fallback
        }

        let resolvedWindow = window
            ?? view?.window
            ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)

        guard let override = resolvedWindow?.overrideUserInterfaceStyle,
              override != .unspecified,
              base.userInterfaceStyle != override
        else {
            return base
        }

        return UITraitCollection(traitsFrom: [
            base,
            UITraitCollection(userInterfaceStyle: override),
        ])
    }

    @MainActor
    static func snapshot(
        for view: UIView? = nil,
        window: UIWindow? = nil,
        fallback: UITraitCollection = .current
    ) -> FireAppearanceSnapshot {
        let traits = traits(for: view, window: window, fallback: fallback)
        return FireAppearanceSnapshot.make(traits: traits, preference: currentPreference)
    }

    static func snapshot(traits: UITraitCollection) -> FireAppearanceSnapshot {
        FireAppearanceSnapshot.make(traits: traits, preference: currentPreference)
    }
}

// MARK: - Texture paint helpers

enum FireAppearanceTexture {
    /// Safe defaults for ASTextNode chrome (stats, headers, footers).
    /// Texture defaults to opaque pure-black fills when background is unset.
    static func configureChromeTextNode(_ node: ASTextNode) {
        node.isOpaque = false
        node.backgroundColor = .clear
        node.displaysAsynchronously = false
        node.placeholderEnabled = false
    }

    static func applyCanvas(_ canvas: UIColor, to node: ASDisplayNode) {
        node.backgroundColor = canvas
        node.isOpaque = true
    }

    static func applyCanvas(_ canvas: UIColor, to view: UIView) {
        view.backgroundColor = canvas
    }
}

// MARK: - Applying protocol

/// Screens that own Texture or baked chrome implement this so theme flips and
/// data reloads share one re-paint entry point.
@MainActor
protocol FireAppearanceApplying: AnyObject {
    func applyAppearance(_ snapshot: FireAppearanceSnapshot)
}
