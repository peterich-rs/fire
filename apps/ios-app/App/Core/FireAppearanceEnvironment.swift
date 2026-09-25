import AsyncDisplayKit
import Combine
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
    let preference: FireAppearancePreference
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
            preference: preference,
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

    static func == (lhs: FireAppearanceSnapshot, rhs: FireAppearanceSnapshot) -> Bool {
        lhs.token == rhs.token
            && lhs.preference == rhs.preference
            && lhs.userInterfaceStyle == rhs.userInterfaceStyle
            && lhs.canvas.cgColor == rhs.canvas.cgColor
            && lhs.ink.cgColor == rhs.ink.cgColor
    }
}

// MARK: - Environment

/// Single source of truth for app appearance preference → window override →
/// Texture-safe snapshots → publish.
///
/// Preference writes go through `applyPreference`. Root cold-start and external
/// UserDefaults mirrors call `syncFromStorage`. Subscribers observe
/// `.fireAppearancePreferenceDidChange` (object is the preference) and/or
/// `snapshotPublisher`.
enum FireAppearanceEnvironment {
    private static let snapshotSubject = CurrentValueSubject<FireAppearanceSnapshot?, Never>(nil)
    private static var lastAppliedPreference: FireAppearancePreference?
    private static var lastPublishedToken: String?

    static var currentPreference: FireAppearancePreference {
        FireAppearancePreference(
            rawValue: UserDefaults.standard.string(forKey: FireTheme.appearancePreferenceStorageKey) ?? ""
        ) ?? .system
    }

    /// Latest published snapshot (may be nil before first apply/sync).
    static var lastSnapshot: FireAppearanceSnapshot? {
        snapshotSubject.value
    }

    /// Combine stream of snapshots after each successful apply/sync publish.
    static var snapshotPublisher: AnyPublisher<FireAppearanceSnapshot, Never> {
        snapshotSubject
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }

    // MARK: Preference ownership

    /// Authoritative preference change path (settings UI, etc.).
    /// Writes storage, applies window override, global UIKit chrome, then publishes.
    @MainActor
    @discardableResult
    static func applyPreference(
        _ preference: FireAppearancePreference,
        window: UIWindow? = nil,
        publishEvenIfUnchanged: Bool = false
    ) -> FireAppearanceSnapshot {
        let normalized = FireUIKitAppearanceCapsuleControl.normalizedForPicker(preference)
        UserDefaults.standard.set(normalized.rawValue, forKey: FireTheme.appearancePreferenceStorageKey)
        return applyWindowAndPublish(
            preference: normalized,
            window: window,
            forcePublish: publishEvenIfUnchanged
        )
    }

    /// Cold start / UserDefaults mirror: apply stored preference to the window and
    /// rebuild snapshot. Publishes only when preference or appearance token changes
    /// (unless `forcePublish` for cold start).
    @MainActor
    @discardableResult
    static func syncFromStorage(
        window: UIWindow? = nil,
        forcePublish: Bool = false
    ) -> FireAppearanceSnapshot {
        applyWindowAndPublish(
            preference: currentPreference,
            window: window,
            forcePublish: forcePublish
        )
    }

    @MainActor
    private static func applyWindowAndPublish(
        preference: FireAppearancePreference,
        window: UIWindow?,
        forcePublish: Bool
    ) -> FireAppearanceSnapshot {
        let targetWindow = window
            ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)

        switch preference {
        case .system:
            targetWindow?.overrideUserInterfaceStyle = .unspecified
        case .light:
            targetWindow?.overrideUserInterfaceStyle = .light
        case .dark, .oled:
            targetWindow?.overrideUserInterfaceStyle = .dark
        }

        FireTheme.applyGlobalAppearances()
        FireUIKitSkeleton.applyThemeDefaults()

        let traits = traits(for: targetWindow, window: targetWindow)
        let snapshot = FireAppearanceSnapshot.make(traits: traits, preference: preference)

        let preferenceChanged = lastAppliedPreference != preference
        let tokenChanged = lastPublishedToken != snapshot.token
        lastAppliedPreference = preference

        if forcePublish || preferenceChanged || tokenChanged {
            lastPublishedToken = snapshot.token
            snapshotSubject.send(snapshot)
            NotificationCenter.default.post(
                name: .fireAppearancePreferenceDidChange,
                object: preference,
                userInfo: [FireAppearanceUserInfoKey.snapshotToken: snapshot.token]
            )
        } else {
            snapshotSubject.value = snapshot
        }
        return snapshot
    }

    // MARK: Traits / snapshot helpers

    /// Style-coherent traits for baking. Prefer a loaded view; when the window
    /// override has already flipped but the view lags one run loop, force the
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
        } else if let window {
            base = window.traitCollection
        } else {
            base = fallback
        }

        let resolvedWindow = window
            ?? view?.window
            ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)

        // Explicit light/dark override always wins over lagging hierarchy traits.
        if let override = resolvedWindow?.overrideUserInterfaceStyle,
           override != .unspecified {
            if base.userInterfaceStyle != override {
                return UITraitCollection(traitsFrom: [
                    base,
                    UITraitCollection(userInterfaceStyle: override),
                ])
            }
            return base
        }

        // System preference: if preference is fixed light/dark but window is
        // unspecified (should not happen after apply), still force style.
        switch currentPreference {
        case .light where base.userInterfaceStyle != .light:
            return UITraitCollection(traitsFrom: [
                base,
                UITraitCollection(userInterfaceStyle: .light),
            ])
        case .dark, .oled:
            if base.userInterfaceStyle != .dark {
                return UITraitCollection(traitsFrom: [
                    base,
                    UITraitCollection(userInterfaceStyle: .dark),
                ])
            }
            return base
        case .system, .light:
            return base
        }
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

enum FireAppearanceUserInfoKey {
    static let snapshotToken = "fire.appearance.snapshotToken"
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

    static func applySnapshot(_ snapshot: FireAppearanceSnapshot, to node: ASDisplayNode) {
        applyCanvas(snapshot.canvas, to: node)
    }

    static func applySnapshot(_ snapshot: FireAppearanceSnapshot, to view: UIView) {
        applyCanvas(snapshot.canvas, to: view)
    }
}

// MARK: - Applying protocol

/// Screens that own Texture or baked chrome implement this so theme flips and
/// data reloads share one re-paint entry point.
@MainActor
protocol FireAppearanceApplying: AnyObject {
    func applyAppearance(_ snapshot: FireAppearanceSnapshot)
}

extension Notification.Name {
    /// Posted by `FireAppearanceEnvironment` after preference/window sync.
    /// `object` is `FireAppearancePreference`. UserInfo may include snapshot token.
    static let fireAppearancePreferenceDidChange = Notification.Name("fire.appearancePreferenceDidChange")
}
