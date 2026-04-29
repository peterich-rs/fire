import SwiftUI

extension AnyTransition {
    /// NavigationStack push fallback for iOS 17 (when `.zoom` is not
    /// available). Slide from trailing + fade + mild scale at insertion;
    /// reverse on removal. Reduce Motion: degrades to opacity only.
    static func firePush(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        let insertion = AnyTransition.move(edge: .trailing)
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.98))
        let removal = AnyTransition.move(edge: .leading)
            .combined(with: .opacity)
        return .asymmetric(insertion: insertion, removal: removal)
    }

    /// Insert/delete transition for list rows. Slide from leading +
    /// opacity. Reduce Motion: opacity only.
    static func fireListItem(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return AnyTransition.move(edge: .leading)
            .combined(with: .opacity)
    }
}

extension View {
    /// Centralised sheet spring tuning. Apply to the sheet's *content*
    /// view, passing the same binding that drives `.sheet(isPresented:)`
    /// so the spring config is scoped to present/dismiss transactions and
    /// does not override animations triggered by state changes inside
    /// the sheet content.
    ///
    /// Example:
    /// ```
    /// .sheet(isPresented: $showSheet) {
    ///     SheetContent(...)
    ///         .fireSheet(presented: $showSheet)
    /// }
    /// ```
    func fireSheet(presented: Binding<Bool>) -> some View {
        modifier(FireSheetSpringModifier(presented: presented))
    }
}

private struct FireSheetSpringModifier: ViewModifier {
    @Binding var presented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transaction(value: presented) { transaction in
            transaction.animation = FireMotionTokens.spring(
                for: .sheet,
                reduceMotion: reduceMotion
            )
        }
    }
}
