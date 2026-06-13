import SwiftUI
import UIKit
import ConfettiSwiftUI

extension View {
    /// Heart-icon bounce on the active edge of a like toggle, plus a
    /// `.success` haptic when `active` flips to `true`. The view that
    /// owns the icon should pass the bool that drives `heart.fill` vs
    /// `heart`.
    func fireLikeEffect(active: Bool) -> some View {
        modifier(FireSymbolBounceEffect(active: active, hapticOnActivate: .success))
    }

    /// `bookmark.fill` ↔ `bookmark` swap with `symbolEffect(.replace)`
    /// content transition + success haptic on activation.
    func fireBookmarkEffect(active: Bool) -> some View {
        modifier(FireSymbolReplaceEffect(active: active, hapticOnActivate: .success))
    }

    /// Follow button bounce + success haptic when `active` flips true.
    func fireFollowEffect(active: Bool) -> some View {
        modifier(FireSymbolBounceEffect(active: active, hapticOnActivate: .success))
    }

    /// Generic success haptic on the rising edge of `trigger`. Use at
    /// confirmed-positive moments (send success, save success). Skipped
    /// under Reduce Motion's haptics counterpart isn't a thing — Reduce
    /// Motion does not silence haptics — so this fires regardless.
    func fireSuccessFeedback(trigger: some Equatable) -> some View {
        modifier(FireHapticFeedbackModifier(trigger: trigger, feedback: .success))
    }

    func fireErrorFeedback(trigger: some Equatable) -> some View {
        modifier(FireHapticFeedbackModifier(trigger: trigger, feedback: .error))
    }

    func fireSelectionFeedback(trigger: some Equatable) -> some View {
        modifier(FireHapticFeedbackModifier(trigger: trigger, feedback: .selection))
    }

    func fireImpactFeedback(
        trigger: some Equatable,
        style: UIImpactFeedbackGenerator.FeedbackStyle = .medium
    ) -> some View {
        modifier(FireHapticFeedbackModifier(trigger: trigger, feedback: .impact(style)))
    }

    /// Non-repeating pulse on a notification badge symbol on every
    /// incoming `value` change. Suppressed under Reduce Motion.
    func fireBadgePulse(value: some Hashable) -> some View {
        modifier(FireBadgePulseEffect(value: AnyHashable(value)))
    }

    /// Numeric content transition for digit-flip on a `Text` view. Use
    /// for like/view/post/follower counts, unread badge counts, etc.
    func fireNumericChange(value: some Hashable) -> some View {
        modifier(FireNumericChangeEffect(value: AnyHashable(value)))
    }

    /// Primary CTA press: scale to ~0.97 on press + `.selection`
    /// haptic. Apply to the outermost button label.
    func fireCTAPress() -> some View {
        modifier(FireCTAPressEffect())
    }

    /// Centralised swipe-to-reply impact feedback. The gesture host owns
    /// the trigger pulse; FireMotion owns the haptic implementation.
    func fireSwipeReplyFeedback(trigger: some Hashable) -> some View {
        modifier(FireSwipeReplyFeedbackEffect(trigger: AnyHashable(trigger)))
    }

    /// Confetti burst gated by Reduce Motion. `trigger` is a
    /// monotonically incrementing `Int` (or any `BinaryInteger`) — bumping
    /// it once fires one celebration. Use for first-follow milestones,
    /// badge unlocks, etc. Never on per-tap interactions.
    func fireCelebrationConfetti(trigger: Binding<Int>) -> some View {
        modifier(FireCelebrationConfettiEffect(trigger: trigger))
    }
}

// MARK: - Concrete modifiers

private struct FireSymbolBounceEffect: ViewModifier {
    let active: Bool
    let hapticOnActivate: FireHapticFeedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        let hapticContent = content.fireHapticFeedback(active, feedback: hapticOnActivate)
        if reduceMotion {
            hapticContent
        } else if #available(iOS 17, *) {
            hapticContent.symbolEffect(.bounce, value: active)
        } else {
            hapticContent
        }
    }
}

private struct FireSymbolReplaceEffect: ViewModifier {
    let active: Bool
    let hapticOnActivate: FireHapticFeedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        let hapticContent = content.fireHapticFeedback(active, feedback: hapticOnActivate)
        if reduceMotion {
            hapticContent
        } else if #available(iOS 17, *) {
            hapticContent.contentTransition(.symbolEffect(.replace))
        } else {
            hapticContent
        }
    }
}

private struct FireBadgePulseEffect: ViewModifier {
    let value: AnyHashable
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else if #available(iOS 17, *) {
            content.symbolEffect(.pulse, options: .nonRepeating, value: value)
        } else {
            content
        }
    }
}

private struct FireNumericChangeEffect: ViewModifier {
    let value: AnyHashable
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else if #available(iOS 17, *) {
            content
                .contentTransition(.numericText())
                .animation(
                    FireMotionTokens.animation(for: .standard, reduceMotion: false),
                    value: value
                )
        } else {
            content
                .animation(
                    FireMotionTokens.animation(for: .standard, reduceMotion: false),
                    value: value
                )
        }
    }
}

private struct FireCTAPressEffect: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1.0)
            .animation(
                FireMotionTokens.animation(for: .tap, reduceMotion: reduceMotion),
                value: isPressed
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
            .onChange(of: isPressed) { pressed in
                if pressed {
                    FireMotionHaptics.selection()
                }
            }
    }
}

private struct FireCelebrationConfettiEffect: ViewModifier {
    @Binding var trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.confettiCannon(trigger: $trigger, num: reduceMotion ? 0 : 36)
    }
}

private struct FireSwipeReplyFeedbackEffect: ViewModifier {
    let trigger: AnyHashable

    func body(content: Content) -> some View {
        content.fireHapticFeedback(trigger, feedback: .impact(.medium))
    }
}

private enum FireHapticFeedback {
    case success
    case error
    case selection
    case impact(UIImpactFeedbackGenerator.FeedbackStyle)

    func fire() {
        switch self {
        case .success:
            FireMotionHaptics.success()
        case .error:
            FireMotionHaptics.error()
        case .selection:
            FireMotionHaptics.selection()
        case .impact(let style):
            FireMotionHaptics.impact(style)
        }
    }
}

private struct FireHapticFeedbackModifier<Value: Equatable>: ViewModifier {
    let trigger: Value
    let feedback: FireHapticFeedback

    func body(content: Content) -> some View {
        content.onChange(of: trigger) { _ in
            feedback.fire()
        }
    }
}

private extension View {
    func fireHapticFeedback<Value: Equatable>(
        _ trigger: Value,
        feedback: FireHapticFeedback
    ) -> some View {
        modifier(FireHapticFeedbackModifier(trigger: trigger, feedback: feedback))
    }
}

/// One-shot per-session gates for celebration confetti. Static state is
/// fine here because the gates are inherently process-scoped: a relaunch
/// resets them implicitly, which matches the "rare, surprising moment"
/// intent. Logout calls `reset()` so a re-login user still gets a
/// fresh celebration.
@MainActor
enum FireMotionCelebrationGate {
    private static var firstFollowFiredThisSession = false

    /// Returns `true` the first time it is called in this process, then
    /// `false` for every subsequent call until `reset()` is invoked.
    static func consumeFirstFollow() -> Bool {
        guard !firstFollowFiredThisSession else { return false }
        firstFollowFiredThisSession = true
        return true
    }

    static func reset() {
        firstFollowFiredThisSession = false
    }
}

enum FireMotionHaptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
