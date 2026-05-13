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

extension View {
    /// Apply the iOS 18 zoom navigation transition where available,
    /// falling back to the centralised `.firePush` transition on iOS 17.
    /// Apply this to the destination view inside `.navigationDestination`.
    @ViewBuilder
    func fireNavigationPush<ID: Hashable>(
        sourceID: ID,
        namespace: Namespace.ID
    ) -> some View {
        if #available(iOS 18, *) {
            self.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self.fireRespectingReduceMotion { content, reduceMotion in
                content.transition(.firePush(reduceMotion: reduceMotion))
            }
        }
    }

    /// Apply `.matchedTransitionSource(id:in:)` on iOS 18+, no-op on iOS 17.
    /// Use on the row/source view that the destination is "zoomed from".
    @ViewBuilder
    func matchedTransitionSourceIfAvailable<ID: Hashable>(
        id: ID,
        in namespace: Namespace.ID
    ) -> some View {
        if #available(iOS 18, *) {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }
}
