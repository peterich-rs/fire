import SkeletonView
import UIKit

/// Thin facade over Juanpe/SkeletonView. Call sites should only use this API
/// so skeleton theming and Reduce Motion stay centralized.
@MainActor
enum FireUIKitSkeleton {
    private static var didApplyThemeDefaults = false

    /// Apply FireTheme skeleton colors once (safe to call repeatedly).
    static func applyThemeDefaults() {
        guard !didApplyThemeDefaults else { return }
        didApplyThemeDefaults = true

        SkeletonAppearance.default.tintColor = FireTheme.uiSkeletonBase
        SkeletonAppearance.default.gradient = SkeletonGradient(
            baseColor: FireTheme.uiSkeletonBase,
            secondaryColor: FireTheme.uiSkeletonHighlight
        )
        SkeletonAppearance.default.multilineCornerRadius = Int(FireTheme.smallCornerRadius / 2)
        SkeletonAppearance.default.skeletonCornerRadius = Float(FireTheme.smallCornerRadius)
    }

    static func prepare(_ view: UIView) {
        applyThemeDefaults()
        view.isSkeletonable = true
    }

    static func prepareHierarchy(in root: UIView) {
        applyThemeDefaults()
        root.isSkeletonable = true
        root.skeletonCornerRadius = Float(FireTheme.smallCornerRadius)
        for subview in root.subviews {
            prepareHierarchy(in: subview)
        }
    }

    static func show(_ view: UIView, animated: Bool? = nil) {
        applyThemeDefaults()
        view.isSkeletonable = true

        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let shouldAnimate = animated ?? !reduceMotion

        if shouldAnimate {
            view.showAnimatedGradientSkeleton(
                usingGradient: SkeletonGradient(
                    baseColor: FireTheme.uiSkeletonBase,
                    secondaryColor: FireTheme.uiSkeletonHighlight
                )
            )
        } else {
            view.showGradientSkeleton(
                usingGradient: SkeletonGradient(
                    baseColor: FireTheme.uiSkeletonBase,
                    secondaryColor: FireTheme.uiSkeletonHighlight
                )
            )
        }
    }

    static func hide(_ view: UIView) {
        guard view.sk.isSkeletonActive else { return }
        view.hideSkeleton(reloadDataAfter: false)
    }
}
