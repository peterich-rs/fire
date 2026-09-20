# iOS Button Press Motion Research

Date: 2026-08-22

Scope: open-source iOS implementations and official Apple API docs only. The goal is to extract concrete values for press scale, release behavior, spring timing, damping, and the separation between press-down and release/overshoot.

## Source Findings

### Apple API Baselines

- SwiftUI `Animation.interactiveSpring(response:dampingFraction:blendDuration:)` defaults to `response: 0.15`, `dampingFraction: 0.86`, `blendDuration: 0.25`, and Apple describes it as a spring with lower response intended for interactive animations. Source: [Apple Developer Documentation](https://developer.apple.com/documentation/swiftui/animation/interactivespring%28response%3Adampingfraction%3Ablendduration%3A%29).
- SwiftUI `Animation.spring(response:dampingFraction:blendDuration:)` defaults to `response: 0.5`, `dampingFraction: 0.825`, `blendDuration: 0`, preserves velocity when successive spring animations replace one another, and treats response as approximate stiffness/duration. Source: [Apple Developer Documentation](https://developer.apple.com/documentation/swiftui/animation/spring%28response%3Adampingfraction%3Ablendduration%3A%29).
- SwiftUI `Animation.default` is currently a spring with `response: 0.55`, `dampingFraction: 1.0`, `blendDuration: 0.0`; Apple notes older OS releases used ease-in-out. Source: [Apple Developer Documentation](https://developer.apple.com/documentation/swiftui/animation/default).
- UIKit `UIView.animate(... usingSpringWithDamping:initialSpringVelocity:)` defines damping ratio `1` as smooth/no oscillation, with values closer to `0` increasing oscillation; initial velocity is normalized to the animation distance per second. Source: [Apple Developer Documentation](https://developer.apple.com/documentation/uikit/uiview/animate%28withduration%3Adelay%3Ausingspringwithdamping%3Ainitialspringvelocity%3Aoptions%3Aanimations%3Acompletion%3A%29).

### nathangitter/fluid-interfaces

This repo is a UIKit implementation inspired by Apple's WWDC18 "Designing Fluid Interfaces" talk. The README explicitly positions `CalculatorButton.swift` as an iOS Calculator-like button and `FlashlightButton.swift` as an iPhone X lock-screen flashlight-like button. Source: [fluid-interfaces README](https://github.com/nathangitter/fluid-interfaces).

- `CalculatorButton` does not scale. It reacts on `.touchDown` and `.touchDragEnter` by stopping the previous animator and immediately switching to a highlighted color. It releases on `.touchUpInside`, `.touchDragExit`, and `.touchCancel` with `UIViewPropertyAnimator(duration: 0.5, curve: .easeOut)` back to the normal color. Source: [CalculatorButton.swift](https://github.com/nathangitter/fluid-interfaces/blob/master/FluidInterfaces/FluidInterfaces/CalculatorButton.swift).
- `FlashlightButton` uses direct manipulation while the finger is down: scale is computed from force as `1 + (maxWidth / minWidth - 1) * force` with `minWidth: 50` and `maxWidth: 92`, so full force maps to about `1.84x`. Release calls `animateToRest()` with `UISpringTimingParameters(damping: 0.4, response: 0.2)` and an interruptible `UIViewPropertyAnimator`, targeting `transform = scale(1, 1)`. Source: [FlashlightButton.swift](https://github.com/nathangitter/fluid-interfaces/blob/master/FluidInterfaces/FluidInterfaces/FlashlightButton.swift).
- Its `Spring.swift` demo exposes design-friendly spring parameters: damping range `0.1...1`, response range `0.1...2`, defaults `dampingRatio: 0.5` and `frequencyResponse: 1`. Its helper maps `response` and `damping` to `UISpringTimingParameters(mass: 1, stiffness: (2pi / response)^2, damping: 4pi * damping / response)`. Source: [Spring.swift](https://github.com/nathangitter/fluid-interfaces/blob/master/FluidInterfaces/FluidInterfaces/Spring.swift).

### aheze/Prism

Prism's SwiftUI example utilities define reusable button styles with separate press-down and release spring values.

- `ScalingButtonStyle` defaults to `scale = 0.95`, applies `opacity = 0.95` while pressed, and uses different springs for the two directions: press-down `response: 0.19`, `dampingFraction: 0.45`, `blendDuration: 1`; release `response: 0.4`, `dampingFraction: 0.4`, `blendDuration: 1`. Source: [Utilities.swift](https://github.com/aheze/Prism/blob/main/Example/PrismExample/PrismExample/Utilities.swift).
- `PressedButtonStyle` uses an even faster state update spring when pressed (`response: 0.1`, `dampingFraction: 0.6`, `blendDuration: 1`) and the same slower, bouncier release spring (`response: 0.4`, `dampingFraction: 0.4`, `blendDuration: 1`). Source: [Utilities.swift](https://github.com/aheze/Prism/blob/main/Example/PrismExample/PrismExample/Utilities.swift).

### hallee/neumorphic-style

`NeumorphicButtonStyle` is a SwiftUI package style. It changes shadow geometry and only uses a very small scale delta.

- Pressed scale is `0.99`, not a large shrink. It uses `interactiveSpring` with press `response: 0.24`, release `response: 0.3`, shared `dampingFraction: 0.4`, and `blendDuration: 0.6`. Source: [NeumorphicButtonStyle.swift](https://github.com/hallee/neumorphic-style/blob/master/Sources/NeumorphicStyle/NeumorphicButtonStyle.swift).

### SagerNet/sing-box-for-apple

This real SwiftUI iOS app is conservative for bar/button chrome.

- `BarItemButtonStyle` does not scale. It drops opacity to `0.5` while pressed and animates with `.easeOut(duration: 0.12)`. Source: [MainView.swift](https://github.com/SagerNet/sing-box-for-apple/blob/dev/SFI/MainView.swift).
- The same file uses `.spring(response: 0.35, dampingFraction: 0.8)` for bottom accessory view transitions, not for direct button press. Source: [MainView.swift](https://github.com/SagerNet/sing-box-for-apple/blob/dev/SFI/MainView.swift).

### Telegram-iOS

Telegram's Texture/AsyncDisplayKit UI often uses opacity highlight rather than scale for small chrome.

- `ChatPinnedMessageTitlePanelNode` uses `HighlightTrackingButtonNode`/`HighlightableButtonNode` callbacks. Pressing immediately lowers text/line/button alpha to `0.4`; release restores alpha to `1.0` using `animateAlpha(... duration: 0.2)`. Source: [ChatPinnedMessageTitlePanelNode.swift](https://github.com/TelegramMessenger/Telegram-iOS/blob/master/submodules/TelegramUI/Sources/ChatPinnedMessageTitlePanelNode.swift).

### Spring Engine References

These are not button-specific, but they reinforce how iOS-style spring systems structure values for touch-driven interactions.

- Wave's README uses `Spring(dampingRatio: 0.68, response: 0.80)` for a gesture release and passes gesture lift-off velocity into the animation; the example also animates scale to `1.1`. Source: [Wave README](https://github.com/jtrivedi/Wave).
- Motion's README example configures a spring with `response: 0.30`, `damping: 0.64`, and explicit velocity. It also warns not to mix stiffness/damping with response/dampingRatio because they are different parameterizations. Source: [Motion README](https://github.com/b3ll/Motion).
- Pop's README emphasizes retargeting a running `POPSpringAnimation` by updating `toValue`, which is relevant to avoiding stutter when a press/release is interrupted. Source: [Pop README](https://github.com/facebookarchive/pop).

## Strongest Patterns

1. Press-down and release should be separate phases. Real implementations either make press-down immediate (`fluid-interfaces` Calculator, Telegram opacity) or use a faster press spring than release (`Prism`, `neumorphic-style`). A single release-style spring for both directions is likely to feel laggy or wobbly on press-down.

2. Everyday iOS buttons use subtle scale. The strongest concrete scale cluster is `0.95...0.99` for standard SwiftUI button styles. `0.90` or lower appears in examples/gists or highly tactile controls, but not in the stronger iOS app/library references for ordinary buttons.

3. Overshoot is usually implicit spring overshoot, not an explicit `1 -> 0.8 -> 1.2 -> 1` keyframe for normal buttons. Under-damped release springs (`dampingFraction`/damping ratio below `1`) can create small overshoot while still targeting identity. Explicit large scale-up belongs to playful/momentum/force interactions, not normal list/card/button taps.

4. Typical press timing is fast: `response` around `0.10...0.24` or `duration` around `0.10...0.20s`. Apple's `interactiveSpring` default response is `0.15`, Prism uses `0.19`, NeumorphicStyle uses `0.24`, and sing-box uses an opacity-only `0.12s` ease-out.

5. Typical release timing is slower and smoother: `response` around `0.30...0.40` for reusable button styles, or UIKit `duration` around `0.5s` for color-only Calculator-style release. Damping commonly sits below critical damping (`0.4...0.86`) when bounce is desired, but `1.0` is the no-oscillation baseline.

6. Direct manipulation should be interruptible and retargetable. `UIViewPropertyAnimator.isInterruptible = true`, Wave's retargetable animations, Pop's running-animation `toValue` update, and Apple's spring replacement behavior all point to avoiding queued multi-stage animations that cannot absorb a quick second tap or drag-cancel.

7. Opacity-only is a valid native-feeling answer for dense chrome. Telegram and sing-box both avoid scale in compact controls and use immediate/short opacity transitions. Scale should probably be reserved for larger, isolated, touch-forward controls in Fire, not applied uniformly to every tappable view.

## Candidate Parameter Ranges For Fire

These are inferred from the sources above; they are not yet a product-code decision.

- Standard button/card tap: press target `0.95...0.97`; press spring `response: 0.12...0.18`, `dampingFraction: 0.75...1.0`; release spring `response: 0.28...0.36`, `dampingFraction: 0.70...0.85`.
- Compact icon/chip tap: press target `0.92...0.96` only if the element has enough visual mass; otherwise prefer opacity `0.45...0.65` with `0.12...0.20s` release.
- Playful or high-emphasis control: press target may go lower (`0.90...0.94`) and release damping may go lower (`0.45...0.65`), but explicit overshoot above `1.05` should be rare and tied to a deliberate feature identity.
- Avoid a visible `1.2` overshoot for ordinary buttons. The closest strong source for larger scale is `fluid-interfaces` Flashlight, but that is force-driven direct manipulation with haptics and maps force up to `1.84x`; it is not a normal tap bounce.
