import ObjectiveC
import UIKit
import AsyncDisplayKit

extension UIView {
    /// Animate layout/visual changes using FireMotion duration tokens.
    static func fireAnimate(
        kind: FireMotionTokens.Duration = .standard,
        reduceMotion: Bool? = nil,
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        let reduce = reduceMotion ?? UIAccessibility.isReduceMotionEnabled
        let duration = FireMotionTokens.duration(for: kind, reduceMotion: reduce)
        guard duration > 0 else {
            animations()
            completion?(true)
            return
        }
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState],
            animations: animations,
            completion: completion
        )
    }

    /// CTA-style press scale used by UIKit controls while the finger is down.
    func firePressScaleHighlight(isHighlighted: Bool, scale: CGFloat = 0.97) {
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        guard !reduceMotion else {
            transform = .identity
            alpha = 1
            return
        }
        if isHighlighted {
            UIView.performWithoutAnimation {
                transform = CGAffineTransform(scaleX: scale, y: scale)
                alpha = 0.92
            }
        } else {
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                usingSpringWithDamping: 0.7,
                initialSpringVelocity: 0.6,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                self.transform = .identity
                self.alpha = 1
            }
        }
    }

    /// One-shot tactile bounce after a successful tap.
    func fireTapBounce(
        pressedScale: CGFloat = 0.88,
        overshootScale: CGFloat = 1.06
    ) {
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        layer.removeAnimation(forKey: Self.fireTapBounceKey)

        guard !reduceMotion else {
            transform = .identity
            alpha = 1
            return
        }

        alpha = 1
        // Keep the model at identity so collection/layout passes cannot snap a
        // mid-flight UIView.transform. Presentation lives on one CA channel.
        transform = .identity

        let animation = CAKeyframeAnimation(keyPath: "transform.scale")
        animation.values = [pressedScale, overshootScale, 1.0]
        animation.keyTimes = [0.0, 0.38, 1.0]
        animation.timingFunctions = [
            CAMediaTimingFunction(controlPoints: 0.16, 0.84, 0.32, 1.0),
            CAMediaTimingFunction(controlPoints: 0.22, 0.61, 0.36, 1.0),
        ]
        animation.duration = 0.42
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = true
        layer.add(animation, forKey: Self.fireTapBounceKey)
    }

    static let fireTapBounceKey = "fire.motion.tapBounce"
}

/// Shared press-bounce profiles for buttons / chips.
enum FirePressBounceStyle: Int {
    /// Primary CTA (login / send / submit).
    case button
    /// Compact icon or toolbar control.
    case compact
    /// Small chips (reactions).
    case chip

    var pressedScale: CGFloat {
        switch self {
        case .button: return 0.94
        case .compact: return 0.88
        case .chip: return 0.80
        }
    }

    var overshootScale: CGFloat {
        switch self {
        case .button: return 1.03
        case .compact: return 1.06
        case .chip: return 1.10
        }
    }
}

extension UIControl {
    private static var firePressBounceStyleKey: UInt8 = 0
    private static var firePressBounceBoundKey: UInt8 = 0

    /// Binds hold-to-press + release bounce on this control.
    /// Safe to call multiple times; only binds once per control.
    func fireBindPressBounce(_ style: FirePressBounceStyle = .button) {
        objc_setAssociatedObject(
            self,
            &Self.firePressBounceStyleKey,
            style.rawValue,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        let alreadyBound = (objc_getAssociatedObject(self, &Self.firePressBounceBoundKey) as? Bool) ?? false
        guard !alreadyBound else { return }
        objc_setAssociatedObject(
            self,
            &Self.firePressBounceBoundKey,
            true,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )

        addTarget(self, action: #selector(firePressBounceTouchDown), for: .touchDown)
        addTarget(self, action: #selector(firePressBounceTouchDown), for: .touchDragEnter)
        addTarget(
            self,
            action: #selector(firePressBounceCancel),
            for: [.touchDragExit, .touchCancel, .touchUpOutside]
        )
        addTarget(self, action: #selector(firePressBounceTouchUpInside), for: .touchUpInside)
    }

    /// Light selection haptic on `.touchUpInside` without replacing existing targets.
    func fireBindSelectionHaptic() {
        removeTarget(self, action: #selector(fireHandleSelectionHaptic), for: .touchUpInside)
        addTarget(self, action: #selector(fireHandleSelectionHaptic), for: .touchUpInside)
    }

    @objc
    private func fireHandleSelectionHaptic() {
        FireMotionHaptics.selection()
    }

    @objc
    private func firePressBounceTouchDown() {
        guard isEnabled else { return }
        let style = fireResolvedPressBounceStyle()
        firePressScaleHighlight(isHighlighted: true, scale: style.pressedScale)
    }

    @objc
    private func firePressBounceCancel() {
        firePressScaleHighlight(isHighlighted: false)
    }

    @objc
    private func firePressBounceTouchUpInside() {
        guard isEnabled else {
            firePressScaleHighlight(isHighlighted: false)
            return
        }
        let style = fireResolvedPressBounceStyle()
        fireTapBounce(
            pressedScale: style.pressedScale,
            overshootScale: style.overshootScale
        )
    }

    private func fireResolvedPressBounceStyle() -> FirePressBounceStyle {
        let raw = objc_getAssociatedObject(self, &Self.firePressBounceStyleKey) as? Int
        return FirePressBounceStyle(rawValue: raw ?? FirePressBounceStyle.button.rawValue) ?? .button
    }
}

extension ASButtonNode {
    private static var firePressBounceStyleKey: UInt8 = 0
    private static var firePressBounceBoundKey: UInt8 = 0

    /// Texture button equivalent of `UIControl.fireBindPressBounce`.
    func fireBindPressBounce(_ style: FirePressBounceStyle = .compact) {
        objc_setAssociatedObject(
            self,
            &Self.firePressBounceStyleKey,
            style.rawValue,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        let alreadyBound = (objc_getAssociatedObject(self, &Self.firePressBounceBoundKey) as? Bool) ?? false
        guard !alreadyBound else { return }
        objc_setAssociatedObject(
            self,
            &Self.firePressBounceBoundKey,
            true,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )

        addTarget(self, action: #selector(fireASPressBounceTouchDown), forControlEvents: .touchDown)
        addTarget(
            self,
            action: #selector(fireASPressBounceCancel),
            forControlEvents: [.touchUpOutside, .touchCancel]
        )
        addTarget(self, action: #selector(fireASPressBounceTouchUpInside), forControlEvents: .touchUpInside)
    }

    @objc
    private func fireASPressBounceTouchDown() {
        guard isEnabled else { return }
        let style = fireResolvedPressBounceStyle()
        view.firePressScaleHighlight(isHighlighted: true, scale: style.pressedScale)
    }

    @objc
    private func fireASPressBounceCancel() {
        view.firePressScaleHighlight(isHighlighted: false)
    }

    @objc
    private func fireASPressBounceTouchUpInside() {
        guard isEnabled else {
            view.firePressScaleHighlight(isHighlighted: false)
            return
        }
        let style = fireResolvedPressBounceStyle()
        view.fireTapBounce(
            pressedScale: style.pressedScale,
            overshootScale: style.overshootScale
        )
    }

    private func fireResolvedPressBounceStyle() -> FirePressBounceStyle {
        let raw = objc_getAssociatedObject(self, &Self.firePressBounceStyleKey) as? Int
        return FirePressBounceStyle(rawValue: raw ?? FirePressBounceStyle.compact.rawValue) ?? .compact
    }
}
