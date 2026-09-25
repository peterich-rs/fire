import UIKit

/// Tab-owned and secondary-page navigation shell.
///
/// Secondary topic routes are presented full-screen above the tab shell (Android multi-Activity
/// analogue). That presented host sets `allowsInteractiveDismissWhenAtRoot` so the root page can
/// swipe away and reveal the untouched tab bar underneath. In-stack pops also carry a navigation-bar
/// snapshot so chrome slides with the outgoing page.
final class FireMainNavigationController: UINavigationController,
    UIGestureRecognizerDelegate,
    UINavigationControllerDelegate,
    UIViewControllerTransitioningDelegate
{
    private enum FullScreenPop {
        static let parallaxDistanceRatio: CGFloat = 0.28
        static let finishProgress: CGFloat = 0.34
        static let finishVelocityX: CGFloat = 720
        static let horizontalBias: CGFloat = 1.08
    }

    /// When true, a rightward pan on the root controller interactively dismisses this
    /// navigation controller (used by the app-root secondary page stack).
    var allowsInteractiveDismissWhenAtRoot = false

    /// Called after this controller finishes dismissing as a presented secondary stack.
    var onDidDismissCompletely: (() -> Void)?

    private let hidesNavigationBarAtRoot: Bool
    private lazy var popAnimator = FireMainCardAnimator(
        operation: .pop,
        parallaxDistanceRatio: FullScreenPop.parallaxDistanceRatio
    )
    private lazy var presentAnimator = FireMainCardAnimator(
        operation: .push,
        parallaxDistanceRatio: FullScreenPop.parallaxDistanceRatio
    )
    private lazy var dismissAnimator = FireMainCardAnimator(
        operation: .pop,
        parallaxDistanceRatio: FullScreenPop.parallaxDistanceRatio
    )
    private var interactionController: UIPercentDrivenInteractiveTransition?
    private var isInteractiveDismiss = false
    private var pendingNavigationBarSnapshot: UIView?
    private lazy var fullScreenPopGestureRecognizer: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(
            target: self,
            action: #selector(handleFullScreenPopPan(_:))
        )
        gesture.maximumNumberOfTouches = 1
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()

    init(rootViewController: UIViewController, hidesNavigationBarAtRoot: Bool = false) {
        self.hidesNavigationBarAtRoot = hidesNavigationBarAtRoot
        super.init(rootViewController: rootViewController)
        delegate = self
        transitioningDelegate = self
        setNavigationBarHidden(hidesNavigationBarAtRoot, animated: false)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.isEnabled = false
        view.addGestureRecognizer(fullScreenPopGestureRecognizer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Secondary stack finished dismissing — release the root coordinator's host reference.
        guard allowsInteractiveDismissWhenAtRoot, isBeingDismissed else { return }
        let callback = onDidDismissCompletely
        onDidDismissCompletely = nil
        callback?()
    }

    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        if !viewControllers.isEmpty {
            setNavigationBarHidden(false, animated: animated)
        }
        super.pushViewController(viewController, animated: animated)
    }

    @discardableResult
    override func popViewController(animated: Bool) -> UIViewController? {
        if animated, viewControllers.count > 1 {
            captureNavigationBarSnapshotIfNeeded()
        }
        return super.popViewController(animated: animated)
    }

    @objc private func handleFullScreenPopPan(_ gestureRecognizer: UIPanGestureRecognizer) {
        let translation = gestureRecognizer.translation(in: view)
        let progress = min(max(translation.x / max(view.bounds.width, 1), 0), 1)

        switch gestureRecognizer.state {
        case .began:
            interactionController = UIPercentDrivenInteractiveTransition()
            if viewControllers.count > 1 {
                isInteractiveDismiss = false
                if popViewController(animated: true) == nil {
                    clearInteractionState()
                }
            } else if canInteractivelyDismissRoot {
                isInteractiveDismiss = true
                pendingNavigationBarSnapshot = nil
                dismiss(animated: true)
            } else {
                clearInteractionState()
            }
        case .changed:
            interactionController?.update(progress)
        case .ended:
            let velocityX = gestureRecognizer.velocity(in: view).x
            if shouldFinishFullScreenPop(progress: progress, velocityX: velocityX) {
                interactionController?.finish()
            } else {
                interactionController?.cancel()
            }
            clearInteractionState()
        case .cancelled, .failed:
            interactionController?.cancel()
            clearInteractionState()
        default:
            break
        }
    }

    func canBeginFullScreenPop(velocity: CGPoint) -> Bool {
        guard transitionCoordinator == nil,
              presentedViewController == nil,
              velocity.x > 0 else {
            return false
        }
        let canPop = viewControllers.count > 1
        let canDismiss = canInteractivelyDismissRoot
        guard canPop || canDismiss else {
            return false
        }
        return abs(velocity.x) > abs(velocity.y) * FullScreenPop.horizontalBias
    }

    func shouldFinishFullScreenPop(progress: CGFloat, velocityX: CGFloat) -> Bool {
        progress >= FullScreenPop.finishProgress || velocityX >= FullScreenPop.finishVelocityX
    }

    func navigationController(
        _ navigationController: UINavigationController,
        willShow viewController: UIViewController,
        animated: Bool
    ) {
        updateNavigationBarVisibility(for: viewController, animated: animated)
        interactivePopGestureRecognizer?.isEnabled = false
        updateSecondaryRootBackItemIfNeeded(for: viewController)
    }

    /// Root page of the secondary stack has no system back target — provide an explicit dismiss control.
    private func updateSecondaryRootBackItemIfNeeded(for viewController: UIViewController) {
        guard allowsInteractiveDismissWhenAtRoot else { return }
        let isRoot = viewControllers.first === viewController
        guard isRoot else { return }
        // Leave pages that already own their chrome (e.g. topic detail) untouched.
        if viewController.navigationItem.leftBarButtonItem != nil
            || !(viewController.navigationItem.leftBarButtonItems ?? []).isEmpty {
            return
        }
        let dismissItem = UIBarButtonItem(
            image: UIImage(systemName: "chevron.backward"),
            style: .plain,
            target: self,
            action: #selector(dismissSecondaryRoot)
        )
        dismissItem.accessibilityLabel = "返回"
        viewController.navigationItem.leftBarButtonItem = dismissItem
    }

    @objc private func dismissSecondaryRoot() {
        dismiss(animated: true)
    }

    func navigationController(
        _ navigationController: UINavigationController,
        animationControllerFor operation: UINavigationController.Operation,
        from fromVC: UIViewController,
        to toVC: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        guard operation == .pop else { return nil }
        popAnimator.navigationBarSnapshot = pendingNavigationBarSnapshot
        popAnimator.navigationBarSnapshotHost = view
        pendingNavigationBarSnapshot = nil
        return popAnimator
    }

    func navigationController(
        _ navigationController: UINavigationController,
        interactionControllerFor animationController: UIViewControllerAnimatedTransitioning
    ) -> UIViewControllerInteractiveTransitioning? {
        isInteractiveDismiss ? nil : interactionController
    }

    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        guard presented === self else { return nil }
        presentAnimator.navigationBarSnapshot = nil
        presentAnimator.navigationBarSnapshotHost = nil
        return presentAnimator
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard dismissed === self else { return nil }
        dismissAnimator.navigationBarSnapshot = nil
        dismissAnimator.navigationBarSnapshotHost = nil
        return dismissAnimator
    }

    func interactionControllerForDismissal(
        using animator: UIViewControllerAnimatedTransitioning
    ) -> UIViewControllerInteractiveTransitioning? {
        isInteractiveDismiss ? interactionController : nil
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === fullScreenPopGestureRecognizer,
              let panGesture = gestureRecognizer as? UIPanGestureRecognizer else {
            return true
        }
        return canBeginFullScreenPop(velocity: panGesture.velocity(in: view))
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }

    func updateNavigationBarVisibility(for viewController: UIViewController, animated: Bool) {
        let isRoot = viewControllers.first === viewController
        setNavigationBarHidden(hidesNavigationBarAtRoot && isRoot, animated: animated)
    }

    private var canInteractivelyDismissRoot: Bool {
        allowsInteractiveDismissWhenAtRoot
            && viewControllers.count <= 1
            && presentingViewController != nil
            && presentedViewController == nil
    }

    private func captureNavigationBarSnapshotIfNeeded() {
        guard !isNavigationBarHidden else {
            pendingNavigationBarSnapshot = nil
            return
        }
        pendingNavigationBarSnapshot = navigationBar.snapshotView(afterScreenUpdates: false)
    }

    private func clearInteractionState() {
        interactionController = nil
        isInteractiveDismiss = false
    }
}
