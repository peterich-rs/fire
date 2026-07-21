import UIKit

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

    /// CTA-style press scale used by UIKit controls.
    func firePressScaleHighlight(isHighlighted: Bool, scale: CGFloat = 0.97) {
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let target = isHighlighted && !reduceMotion ? scale : 1.0
        UIView.fireAnimate(kind: .tap, reduceMotion: reduceMotion) {
            self.transform = CGAffineTransform(scaleX: target, y: target)
        }
    }
}

extension UIControl {
    /// Light selection haptic on `.touchUpInside` without replacing existing targets.
    func fireBindSelectionHaptic() {
        removeTarget(self, action: #selector(fireHandleSelectionHaptic), for: .touchUpInside)
        addTarget(self, action: #selector(fireHandleSelectionHaptic), for: .touchUpInside)
    }

    @objc
    private func fireHandleSelectionHaptic() {
        FireMotionHaptics.selection()
    }
}
