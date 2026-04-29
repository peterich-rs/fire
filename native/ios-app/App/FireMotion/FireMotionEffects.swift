import SwiftUI
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
        sensoryFeedback(.success, trigger: trigger)
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
    let hapticOnActivate: SensoryFeedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        Group {
            if reduceMotion {
                content
            } else {
                content.symbolEffect(.bounce, value: active)
            }
        }
        // Spec: ".sensoryFeedback(.success) on success" for like/bookmark/follow
        // toggles. The haptic must fire on both activation and deactivation
        // (every confirmed state flip), so trigger on the raw `active` value.
        .sensoryFeedback(hapticOnActivate, trigger: active)
    }
}

private struct FireSymbolReplaceEffect: ViewModifier {
    let active: Bool
    let hapticOnActivate: SensoryFeedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        Group {
            if reduceMotion {
                content
            } else {
                content.contentTransition(.symbolEffect(.replace))
            }
        }
        .sensoryFeedback(hapticOnActivate, trigger: active)
    }
}

private struct FireBadgePulseEffect: ViewModifier {
    let value: AnyHashable
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.symbolEffect(.pulse, options: .nonRepeating, value: value)
        }
    }
}

private struct FireNumericChangeEffect: ViewModifier {
    let value: AnyHashable
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(
                FireMotionTokens.animation(for: .standard, reduceMotion: reduceMotion),
                value: value
            )
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
            .sensoryFeedback(.selection, trigger: isPressed) { _, newValue in
                newValue
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
        content.sensoryFeedback(.impact(weight: .medium), trigger: trigger)
    }
}
