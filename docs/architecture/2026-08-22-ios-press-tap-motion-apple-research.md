# iOS Press/Tap Motion: Apple-First Research

Date: 2026-08-22  
Scope: Apple primary sources only. Third-party libraries and non-Apple commentary are intentionally excluded.  
Purpose: guide Fire's iOS button/chip press feedback tuning without inventing undocumented Apple defaults.

## Primary Sources

- [Apple Human Interface Guidelines: Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)
- [Apple Human Interface Guidelines: Motion](https://developer.apple.com/design/human-interface-guidelines/motion)
- [Apple Human Interface Guidelines: Gestures](https://developer.apple.com/design/human-interface-guidelines/gestures)
- [Apple Human Interface Guidelines: Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback)
- [Apple Human Interface Guidelines: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [WWDC18: Designing Fluid Interfaces](https://developer.apple.com/videos/play/wwdc2018/803/)
- [UIKit: UIControl.State.highlighted](https://developer.apple.com/documentation/uikit/uicontrol/state-swift.struct/highlighted)
- [UIKit: UIControl.isHighlighted](https://developer.apple.com/documentation/uikit/uicontrol/ishighlighted)
- [UIKit: UIButton.configurationUpdateHandler](https://developer.apple.com/documentation/uikit/uibutton/configurationupdatehandler-swift.property)
- [SwiftUI: ButtonStyle](https://developer.apple.com/documentation/swiftui/buttonstyle)
- [SwiftUI: ButtonStyleConfiguration](https://developer.apple.com/documentation/swiftui/buttonstyleconfiguration)
- [UIKit: UIView.animate spring API](https://developer.apple.com/documentation/uikit/uiview/animate%28withduration%3Adelay%3Ausingspringwithdamping%3Ainitialspringvelocity%3Aoptions%3Aanimations%3Acompletion%3A%29)
- [UIKit: UIViewPropertyAnimator](https://developer.apple.com/documentation/uikit/uiviewpropertyanimator)
- [UIKit: UIView.AnimationOptions.allowUserInteraction](https://developer.apple.com/documentation/uikit/uiview/animationoptions/allowuserinteraction)
- [UIKit: UIFeedbackGenerator.prepare()](https://developer.apple.com/documentation/uikit/uifeedbackgenerator/prepare%28%29)
- [Apple HIG: Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)

## What Apple States Directly

1. Custom buttons need an explicit pressed state. Apple says a custom button without a press state can feel unresponsive, and system buttons provide built-in interaction states. Source: [HIG Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons).

2. The pressed state should start on touch-down, not after activation. In WWDC18's tap example, Apple describes a button highlighting immediately on touch-down to show the system is reacting, while tap confirmation waits until touch-up. Source: [WWDC18 Designing Fluid Interfaces](https://developer.apple.com/videos/play/wwdc2018/803/).

3. A tap must remain cancelable before touch-up. WWDC18 describes extra tap-area margin, dragging outside to cancel, and dragging back in to re-highlight and allow confirmation. Source: [WWDC18 Designing Fluid Interfaces](https://developer.apple.com/videos/play/wwdc2018/803/).

4. UIKit already models this lifecycle through `highlighted`. `UIControl.State.highlighted` is entered when a touch enters the control bounds and cleared on touch-up or touch exit; `UIControl.isHighlighted` is automatically set and cleared in response to appropriate touch events. Sources: [UIControl.State.highlighted](https://developer.apple.com/documentation/uikit/uicontrol/state-swift.struct/highlighted), [UIControl.isHighlighted](https://developer.apple.com/documentation/uikit/uicontrol/ishighlighted).

5. For configured UIKit buttons, Apple exposes `configurationUpdateHandler` specifically to update button configuration when button state changes. Source: [UIButton.configurationUpdateHandler](https://developer.apple.com/documentation/uikit/uibutton/configurationupdatehandler-swift.property).

6. SwiftUI separates standard button interaction from custom interaction. `ButtonStyle` applies custom appearance while keeping the platform's standard button interaction behavior; `ButtonStyleConfiguration.isPressed` reports the current press state. `PrimitiveButtonStyle` is the path for custom interaction behavior. Sources: [SwiftUI ButtonStyle](https://developer.apple.com/documentation/swiftui/buttonstyle), [SwiftUI ButtonStyleConfiguration](https://developer.apple.com/documentation/swiftui/buttonstyleconfiguration).

7. Gesture feedback should be immediate and continuous. Apple's gesture guidance says useful gestures provide immediate feedback, and WWDC18 says taps, presses, and every object interaction need to respond instantly. Sources: [HIG Gestures](https://developer.apple.com/design/human-interface-guidelines/gestures), [WWDC18 Designing Fluid Interfaces](https://developer.apple.com/videos/play/wwdc2018/803/).

8. Motion for feedback should be brief, precise, purposeful, and unobtrusive. Apple says feedback animation should be brief and precise, and generally discourages adding motion to frequent app interactions because standard components already provide subtle animation. Sources: [HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion), [HIG Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback).

9. Apple favors redirectable/interruption-friendly interactions over fixed call-and-response animations. WWDC18 frames fluid interfaces as behavior that works in concert with the interaction rather than a static timed animation that takes control away until it finishes. `UIViewPropertyAnimator` supports starting, pausing, stopping, reversing, scrubbing, and continuing animations, and has an `isInterruptible` property. Sources: [WWDC18 Designing Fluid Interfaces](https://developer.apple.com/videos/play/wwdc2018/803/), [UIViewPropertyAnimator](https://developer.apple.com/documentation/uikit/uiviewpropertyanimator).

10. UIKit's spring API defines useful numeric semantics even though it does not publish standard button scale values. A damping ratio of `1` decelerates without oscillation; damping closer to `0` increases oscillation. Apple also says initial spring velocity should match the view's velocity before attachment, and `1` velocity means the full animation distance per second. Source: [UIView.animate spring API](https://developer.apple.com/documentation/uikit/uiview/animate%28withduration%3Adelay%3Ausingspringwithdamping%3Ainitialspringvelocity%3Aoptions%3Aanimations%3Acompletion%3A%29).

11. Animations should not block interaction unless blocking is intentional. `UIView.AnimationOptions.allowUserInteraction` exists to allow views to receive interaction during an animation, and HIG Motion says people should be able to cancel motion and should not need to wait for repeated animations to finish. Sources: [UIView.AnimationOptions.allowUserInteraction](https://developer.apple.com/documentation/uikit/uiview/animationoptions/allowuserinteraction), [HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion).

12. Haptics can complement visual press feedback, but need to be coherent and low-latency. Apple says haptics should complement other feedback, match the intensity and sharpness of accompanying animation, and avoid overuse. `UIFeedbackGenerator.prepare()` places the generator in a prepared state for lower-latency feedback when called before the event. Sources: [HIG Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics), [UIFeedbackGenerator.prepare()](https://developer.apple.com/documentation/uikit/uifeedbackgenerator/prepare%28%29).

13. Reduced Motion should tighten this behavior. Apple accessibility guidance says that when Reduce Motion is active, apps should reduce automatic and repetitive animations, including zooming/scaling, and specifically lists tightening animation springs to reduce bounce effects. Sources: [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion).

## What Apple Does Not Publish

Apple's public HIG, UIKit, and SwiftUI references do not publish a single numeric scale path for a standard iOS button press, such as `1.00 -> 0.95 -> 1.00` or `1.00 -> 0.90 -> 1.03 -> 1.00`. They expose state lifecycles, timing tools, spring semantics, and qualitative motion guidance instead. Sources reviewed: [HIG Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons), [HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion), [UIButton.configurationUpdateHandler](https://developer.apple.com/documentation/uikit/uibutton/configurationupdatehandler-swift.property), [SwiftUI ButtonStyle](https://developer.apple.com/documentation/swiftui/buttonstyle), [UIView.animate spring API](https://developer.apple.com/documentation/uikit/uiview/animate%28withduration%3Adelay%3Ausingspringwithdamping%3Ainitialspringvelocity%3Aoptions%3Aanimations%3Acompletion%3A%29).

## Open-Source Reference Points

These are not Apple sources; they are included as ecosystem calibration points because Fire also needs a pragmatic implementation choice.

- [SquishButton](https://github.com/BalestraPatrick/SquishButton) is explicitly modeled after the Clips record button, not a generic app button. Its README exposes `scaling = 10` pixels and `animationDuration = 0.15`, which confirms that strong squash can be appropriate for a special-purpose record affordance but is not evidence for default list chips or toolbar icons. Source: [SquishButton README](https://github.com/BalestraPatrick/SquishButton).

- [PMSuperButton](https://github.com/pmusolino/PMSuperButton) is a broad `UIButton` subclass with highlighted/selected animations, ripple effects, gradients, loaders, and Interface Builder customization. It is a useful catalog of button affordances, but it is not a narrow press-motion dependency. Source: [PMSuperButton README](https://github.com/pmusolino/PMSuperButton).

- [DOFavoriteButton](https://github.com/okmr-d/DOFavoriteButton) is a celebratory state-change button, not a generic press feedback layer. Its README exposes a customizable `duration` with default `1.0`, which is appropriate for a favorite/star animation but too long for routine touch-down/touch-up feedback. Source: [DOFavoriteButton README](https://github.com/okmr-d/DOFavoriteButton).

- Apple’s newer SwiftUI spring presets provide a more relevant baseline for everyday controls than most third-party button libraries. `interactiveSpring(response:dampingFraction:blendDuration:)` defaults to `0.15 / 0.86 / 0.25`, `snappy(duration:extraBounce:)` uses base bounce `0.15`, and `bouncy(duration:extraBounce:)` uses base bounce `0.3`. Sources: [interactiveSpring(response:dampingFraction:blendDuration:)](https://developer.apple.com/documentation/swiftui/animation/interactivespring%28response%3Adampingfraction%3Ablendduration%3A%29), [snappy(duration:extraBounce:)](https://developer.apple.com/documentation/swiftui/animation/snappy%28duration%3Aextrabounce%3A%29), [bouncy(duration:extraBounce:)](https://developer.apple.com/documentation/swiftui/animation/bouncy%28duration%3Aextrabounce%3A%29).

## Dependency Fit For Fire

Fire should not pull one of the above libraries in as the implementation path for tap feedback.

1. Fire needs one shared motion model across UIKit `UIButton`, Texture `ASButtonNode`, and a small SwiftUI surface. The surveyed libraries are mainly `UIButton` subclasses or special-purpose controls, so adopting one would still leave Fire maintaining a second motion system. Sources: [PMSuperButton README](https://github.com/pmusolino/PMSuperButton), [SquishButton README](https://github.com/BalestraPatrick/SquishButton), [DOFavoriteButton README](https://github.com/okmr-d/DOFavoriteButton).

2. Fire’s architecture already centralizes press motion in `FireMotionUIKit` and `FireMotionEffects`. A small local retune preserves the repository’s “one authoritative implementation path” rule better than introducing a dependency that only covers part of the UI surface.

3. The best use of these libraries is as reference material: keep Fire’s local shared motion layer, but tune it toward Apple’s lighter interaction springs and away from exaggerated subclass-specific bounce.

## Fire Design Implications

1. Treat `highlighted` / `isPressed` as the authoritative press state. Fire's UIKit path should map touch-down/touch-enter to the pressed visual state, touch-exit/cancel to restoration, and touch-up-inside to activation plus release feedback. This follows Apple's control state model and WWDC tap lifecycle. Sources: [UIControl.State.highlighted](https://developer.apple.com/documentation/uikit/uicontrol/state-swift.struct/highlighted), [UIControl.isHighlighted](https://developer.apple.com/documentation/uikit/uicontrol/ishighlighted), [WWDC18 Designing Fluid Interfaces](https://developer.apple.com/videos/play/wwdc2018/803/).

2. Avoid a large default press range for common buttons and chips. A `0.80` press scale is a 20% linear shrink and a 36% area shrink, so it is visually dominant. Apple does not forbid this, but HIG Motion's guidance for frequent interactions points toward subtle, brief feedback rather than a large animation people must notice every time. Source: [HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion).

3. Prefer a single spring release to a manually chained bounce sequence for standard controls. Apple spring APIs already support overshoot through damping below `1`, and WWDC18 favors continuous dynamic behavior. A fixed `shrink -> overshoot -> settle` chain is easier to make visibly jerky if interrupted. Sources: [UIView.animate spring API](https://developer.apple.com/documentation/uikit/uiview/animate%28withduration%3Adelay%3Ausingspringwithdamping%3Ainitialspringvelocity%3Aoptions%3Aanimations%3Acompletion%3A%29), [WWDC18 Designing Fluid Interfaces](https://developer.apple.com/videos/play/wwdc2018/803/), [UIViewPropertyAnimator](https://developer.apple.com/documentation/uikit/uiviewpropertyanimator).

4. If Fire uses overshoot, make it purposeful and tiered. WWDC18 says bounciness should be purposeful and balanced with utility. That supports reserving stronger bounce for playful or high-salience affordances, while keeping dense list chips, reaction chips, and composer buttons restrained. Source: [WWDC18 Designing Fluid Interfaces](https://developer.apple.com/videos/play/wwdc2018/803/).

5. The pressed transition should not be instantaneous if it creates a visible snap. Apple requires immediate response, not necessarily zero-duration transform mutation. A very short touch-down animation can preserve responsiveness while avoiding the "jump" produced by setting transform directly. Sources: [HIG Gestures](https://developer.apple.com/design/human-interface-guidelines/gestures), [WWDC18 Designing Fluid Interfaces](https://developer.apple.com/videos/play/wwdc2018/803/).

6. Any Fire press animation should start from the current presentation state and remain interruptible. Users can press, drag out, drag back in, or tap repeatedly; Apple explicitly emphasizes redirection and cancelability. Sources: [WWDC18 Designing Fluid Interfaces](https://developer.apple.com/videos/play/wwdc2018/803/), [UIViewPropertyAnimator](https://developer.apple.com/documentation/uikit/uiviewpropertyanimator), [UIView.AnimationOptions.allowUserInteraction](https://developer.apple.com/documentation/uikit/uiview/animationoptions/allowuserinteraction).

7. Reduced Motion should remove or sharply reduce bounce, not merely shorten the same curve. Apple's accessibility guidance calls out zooming/scaling and bounce effects specifically. Sources: [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion).

## Practical Tuning Guardrails

These are Fire-local implications, not Apple-published defaults.

- Common controls: use subtle scale deltas and no obvious overshoot by default. This aligns with Apple's guidance for frequent UI interactions to stay lightweight and unobtrusive. Source basis: [HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion).

- Prominent one-shot actions: a modest overshoot can be acceptable if it reinforces completion, but the damping should stay high enough that it does not oscillate. Source basis: [UIView.animate spring API](https://developer.apple.com/documentation/uikit/uiview/animate%28withduration%3Adelay%3Ausingspringwithdamping%3Ainitialspringvelocity%3Aoptions%3Aanimations%3Acompletion%3A%29), [WWDC18 Designing Fluid Interfaces](https://developer.apple.com/videos/play/wwdc2018/803/).

- Dense chips and reaction pills: prefer highlight/opacity/material response plus a very small scale change, because they are frequent and sit inside scrollable content. Source basis: [HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion), [HIG Gestures](https://developer.apple.com/design/human-interface-guidelines/gestures).

- Strong `1.00 -> 0.80 -> 1.20 -> 1.00` motion should be considered a special-effect tier, not the default iOS button press style for Fire. Source basis: [HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion), [WWDC18 Designing Fluid Interfaces](https://developer.apple.com/videos/play/wwdc2018/803/), [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility).

## Fire 2026-08-22 Tuning Choice

The chosen Fire direction is:

- animate into the pressed state quickly instead of jumping there instantly
- release with one short spring toward identity instead of a fixed manual `press -> overshoot -> settle` chain
- keep press scales restrained for frequent controls
- reserve stronger bounce for special-purpose affordances, not generic buttons/chips

That leads to shared scales closer to `0.96 / 0.94 / 0.93` for `button / compact / chip`, with an interactive release spring tuned closer to Apple’s `interactiveSpring` baseline than to a highly bouncy custom sequence.

## Verification Checklist For A Future Code Change

- Touch-down produces visible feedback immediately.
- Touch-up-inside confirms the action and releases feedback.
- Touch-exit/cancel restores feedback without activating.
- Drag-out and drag-back-in re-enter the pressed state.
- Repeated taps do not stack animations or jump transforms.
- While a release animation is running, the control remains interactive unless intentionally disabled.
- Reduce Motion eliminates or tightens bounce and avoids repetitive scaling.
- Haptics, if used, are prepared before the triggering event and remain proportional to the visual motion.
