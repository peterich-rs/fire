import UIKit

final class FireMainTabBarController: UITabBarController, UITabBarControllerDelegate {
    var onSelectedTabChanged: ((Int) -> Void)?

    private let navigationState: FireNavigationState
    private let viewModel: FireAppViewModel
    private let homeFeedStore: FireHomeFeedStore
    private let searchStore: FireSearchStore
    private let notificationStore: FireNotificationStore
    private let topicDetailStore: FireTopicDetailStore
    private let profileViewModel: FireProfileViewModel

    init(
        viewModel: FireAppViewModel,
        navigationState: FireNavigationState,
        homeFeedStore: FireHomeFeedStore,
        searchStore: FireSearchStore,
        notificationStore: FireNotificationStore,
        topicDetailStore: FireTopicDetailStore,
        profileViewModel: FireProfileViewModel
    ) {
        self.viewModel = viewModel
        self.navigationState = navigationState
        self.homeFeedStore = homeFeedStore
        self.searchStore = searchStore
        self.notificationStore = notificationStore
        self.topicDetailStore = topicDetailStore
        self.profileViewModel = profileViewModel
        super.init(nibName: nil, bundle: nil)
        delegate = self
        configureAppearance()
        configureTabs()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setSelectedTab(_ index: Int) {
        guard let controllers = viewControllers,
              controllers.indices.contains(index),
              selectedIndex != index else {
            return
        }
        selectedIndex = index
    }

    func setUnreadCount(_ count: Int) {
        guard let notificationsItem = viewControllers?[safe: 1]?.tabBarItem else {
            return
        }
        notificationsItem.badgeValue = count > 0 ? String(count) : nil
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        guard let index = viewControllers?.firstIndex(of: viewController) else {
            return
        }
        onSelectedTabChanged?(index)
    }

    private func configureTabs() {
        let home = makeNavigationController(
            title: "首页",
            systemImage: "house",
            selectedSystemImage: "house.fill",
            rootViewController: FireHomeViewController(
                viewModel: viewModel,
                navigationState: navigationState,
                homeFeedStore: homeFeedStore,
                searchStore: searchStore,
                topicDetailStore: topicDetailStore,
                topicRoutePresenter: FireTopicRoutePresenter.appRoot(
                    navigationState: navigationState,
                    logger: viewModel.topicRouteLogger()
                )
            )
        )
        let notifications = makeNavigationController(
            title: "通知",
            systemImage: "bell",
            selectedSystemImage: "bell.fill",
            rootViewController: FireNotificationsViewController(
                viewModel: viewModel,
                navigationState: navigationState,
                notificationStore: notificationStore,
                topicDetailStore: topicDetailStore
            )
        )
        let profile = makeNavigationController(
            title: "我的",
            systemImage: "person",
            selectedSystemImage: "person.fill",
            rootViewController: FireProfileViewController(
                viewModel: viewModel,
                navigationState: navigationState,
                profileViewModel: profileViewModel,
                topicDetailStore: topicDetailStore
            )
        )
        viewControllers = [home, notifications, profile]
    }

    private func makeNavigationController(
        title: String,
        systemImage: String,
        selectedSystemImage: String,
        rootViewController: UIViewController
    ) -> UINavigationController {
        let navigationController = FireMainNavigationController(rootViewController: rootViewController)
        navigationController.navigationBar.prefersLargeTitles = false
        navigationController.tabBarItem = UITabBarItem(
            title: title,
            image: UIImage(systemName: systemImage),
            selectedImage: UIImage(systemName: selectedSystemImage)
        )
        return navigationController
    }

    private func configureAppearance() {
        tabBar.tintColor = FireTheme.uiAccent
        tabBar.unselectedItemTintColor = FireTheme.uiTertiaryInk

        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        appearance.backgroundColor = FireTheme.uiTabBarBackground
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
    }
}

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

private final class FireMainCardAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    enum Operation {
        case push
        case pop
    }

    private let duration: TimeInterval = 0.28
    private let operation: Operation
    private let parallaxDistanceRatio: CGFloat
    var navigationBarSnapshot: UIView?
    weak var navigationBarSnapshotHost: UIView?

    init(operation: Operation, parallaxDistanceRatio: CGFloat) {
        self.operation = operation
        self.parallaxDistanceRatio = parallaxDistanceRatio
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        duration
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let fromView = transitionContext.view(forKey: .from),
              let toView = transitionContext.view(forKey: .to) else {
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            return
        }

        let containerView = transitionContext.containerView
        let width = max(containerView.bounds.width, 1)
        let toViewController = transitionContext.viewController(forKey: .to)
        if let toViewController {
            toView.frame = transitionContext.finalFrame(for: toViewController)
        } else {
            toView.frame = containerView.bounds
        }

        switch operation {
        case .push:
            // Incoming secondary page slides from the right over the still tab shell.
            toView.transform = CGAffineTransform(translationX: width, y: 0)
            containerView.addSubview(toView)
            applyOutgoingShadow(to: toView)

            UIView.animate(
                withDuration: transitionDuration(using: transitionContext),
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction],
                animations: {
                    toView.transform = .identity
                    fromView.transform = CGAffineTransform(translationX: -width * self.parallaxDistanceRatio, y: 0)
                },
                completion: { _ in
                    let cancelled = transitionContext.transitionWasCancelled
                    fromView.transform = .identity
                    toView.transform = .identity
                    self.clearOutgoingShadow(from: toView)
                    if cancelled {
                        toView.removeFromSuperview()
                    }
                    transitionContext.completeTransition(!cancelled)
                }
            )

        case .pop:
            // Outgoing page slides right. Optional nav-bar snapshot rides with it so the real
            // bar (already swapped to the destination) stays covered — WeChat whole-page card.
            toView.transform = CGAffineTransform(translationX: -width * parallaxDistanceRatio, y: 0)
            containerView.insertSubview(toView, belowSubview: fromView)
            applyOutgoingShadow(to: fromView)

            let barSnapshot = navigationBarSnapshot
            let barHost = navigationBarSnapshotHost
            navigationBarSnapshot = nil
            navigationBarSnapshotHost = nil
            if let barSnapshot, let barHost {
                let barFrame: CGRect
                if let navigationBar = transitionContext.viewController(forKey: .from)?.navigationController?.navigationBar {
                    barFrame = navigationBar.convert(navigationBar.bounds, to: barHost)
                } else {
                    barFrame = CGRect(
                        x: 0,
                        y: barHost.safeAreaInsets.top,
                        width: barHost.bounds.width,
                        height: max(barSnapshot.bounds.height, 44)
                    )
                }
                barSnapshot.frame = barFrame
                barHost.addSubview(barSnapshot)
            }

            UIView.animate(
                withDuration: transitionDuration(using: transitionContext),
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction],
                animations: {
                    fromView.transform = CGAffineTransform(translationX: width, y: 0)
                    barSnapshot?.transform = CGAffineTransform(translationX: width, y: 0)
                    toView.transform = .identity
                },
                completion: { _ in
                    let cancelled = transitionContext.transitionWasCancelled
                    fromView.transform = .identity
                    toView.transform = .identity
                    barSnapshot?.removeFromSuperview()
                    self.clearOutgoingShadow(from: fromView)
                    if cancelled {
                        toView.removeFromSuperview()
                    }
                    transitionContext.completeTransition(!cancelled)
                }
            )
        }
    }

    private func applyOutgoingShadow(to view: UIView) {
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.18
        view.layer.shadowRadius = 12
        view.layer.shadowOffset = CGSize(width: -3, height: 0)
    }

    private func clearOutgoingShadow(from view: UIView) {
        view.layer.shadowOpacity = 0
        view.layer.shadowRadius = 0
        view.layer.shadowOffset = .zero
        view.layer.shadowColor = nil
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
