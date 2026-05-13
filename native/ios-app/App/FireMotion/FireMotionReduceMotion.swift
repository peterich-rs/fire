import SwiftUI

/// Runs `body` only when the user has *not* opted into Reduce Motion. Use
/// at sites where suppression is the right behavior (confetti,
/// non-essential decorative motion). For sites where motion should
/// degrade rather than be skipped entirely, use the duration / transition
/// helpers in `FireMotionTokens` instead.
@MainActor
@discardableResult
func fireRespectingReduceMotion<Result>(
    _ reduceMotion: Bool,
    _ body: () -> Result
) -> Result? {
    guard !reduceMotion else {
        return nil
    }
    return body()
}

extension View {
    /// Reads the current Reduce Motion preference and feeds it to a
    /// caller-supplied builder. Lets call sites compose conditional motion
    /// without scattering `@Environment(\.accessibilityReduceMotion)`
    /// reads across every view.
    func fireRespectingReduceMotion<ModifiedContent: View>(
        @ViewBuilder transform: @escaping (Self, _ reduceMotion: Bool) -> ModifiedContent
    ) -> some View {
        FireMotionReduceMotionWrapper(content: self, transform: transform)
    }
}

private struct FireMotionReduceMotionWrapper<Content: View, ModifiedContent: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let content: Content
    let transform: (Content, Bool) -> ModifiedContent

    var body: some View {
        transform(content, reduceMotion)
    }
}
