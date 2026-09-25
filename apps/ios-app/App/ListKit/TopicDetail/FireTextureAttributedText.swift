import UIKit

/// Texture (`ASTextNode`) async display resolves dynamic `UIColor`s on a background
/// queue that may not carry the window's `userInterfaceStyle`. Baking resolved
/// (static) colors with an explicitly captured trait collection keeps dark-mode
/// body/username text readable on the pure-black canvas.
enum FireTextureAttributedText {
    static func appearanceToken(for traits: UITraitCollection) -> String {
        switch traits.userInterfaceStyle {
        case .dark:
            return "dark"
        case .light:
            return "light"
        case .unspecified:
            return "unspecified"
        @unknown default:
            return "unknown"
        }
    }

    /// Snapshot of the interface style that should be used when building/binding
    /// Texture text. Prefer a loaded view's trait collection; fall back to the
    /// main-thread current traits.
    static func colorTraits(
        from view: UIView? = nil,
        fallback: UITraitCollection = .current
    ) -> UITraitCollection {
        if let view {
            return view.traitCollection
        }
        return fallback
    }

    static func resolvedColor(_ color: UIColor, with traits: UITraitCollection) -> UIColor {
        color.resolvedColor(with: traits)
    }

    static func ink(with traits: UITraitCollection) -> UIColor {
        FireTheme.uiInk.resolvedColor(with: traits)
    }

    static func subtleInk(with traits: UITraitCollection) -> UIColor {
        FireTheme.uiSubtleInk.resolvedColor(with: traits)
    }

    static func tertiaryInk(with traits: UITraitCollection) -> UIColor {
        FireTheme.uiTertiaryInk.resolvedColor(with: traits)
    }

    /// Resolve dynamic foreground/background colors so Texture display does not
    /// depend on the display-queue trait environment.
    static func resolvingDynamicColors(
        _ attributed: NSAttributedString,
        with traits: UITraitCollection
    ) -> NSAttributedString {
        guard attributed.length > 0 else { return attributed }

        let mutable = NSMutableAttributedString(attributedString: attributed)
        let fullRange = NSRange(location: 0, length: mutable.length)
        mutable.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            var updated = attributes
            var changed = false

            if let color = attributes[.foregroundColor] as? UIColor {
                let resolved = color.resolvedColor(with: traits)
                if resolved !== color {
                    updated[.foregroundColor] = resolved
                    changed = true
                } else {
                    // Even when the object identity is stable, force a resolved snapshot.
                    updated[.foregroundColor] = resolved
                    changed = true
                }
            }
            if let color = attributes[.backgroundColor] as? UIColor {
                updated[.backgroundColor] = color.resolvedColor(with: traits)
                changed = true
            }
            if let color = attributes[.strokeColor] as? UIColor {
                updated[.strokeColor] = color.resolvedColor(with: traits)
                changed = true
            }
            if let color = attributes[.underlineColor] as? UIColor {
                updated[.underlineColor] = color.resolvedColor(with: traits)
                changed = true
            }
            if let color = attributes[.strikethroughColor] as? UIColor {
                updated[.strikethroughColor] = color.resolvedColor(with: traits)
                changed = true
            }
            if let color = attributes[.fireQuotePreviewBackgroundColor] as? UIColor {
                updated[.fireQuotePreviewBackgroundColor] = color.resolvedColor(with: traits)
                changed = true
            }
            if let color = attributes[.fireQuotePreviewStripeColor] as? UIColor {
                updated[.fireQuotePreviewStripeColor] = color.resolvedColor(with: traits)
                changed = true
            }

            if changed {
                mutable.setAttributes(updated, range: range)
            }
        }
        return mutable
    }
}
