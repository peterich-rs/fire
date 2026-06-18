import SwiftUI
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
            rootView: AnyView(
                FireProfileTabRootHost(
                    viewModel: viewModel,
                    navigationState: navigationState,
                    profileViewModel: profileViewModel,
                    topicDetailStore: topicDetailStore
                )
            )
        )
        viewControllers = [home, notifications, profile]
    }

    private func makeNavigationController(
        title: String,
        systemImage: String,
        selectedSystemImage: String,
        rootView: AnyView
    ) -> UINavigationController {
        let host = UIHostingController(rootView: rootView)
        host.view.backgroundColor = .systemBackground
        let navigationController = FireMainNavigationController(
            rootViewController: host,
            hidesNavigationBarAtRoot: true
        )
        navigationController.tabBarItem = UITabBarItem(
            title: title,
            image: UIImage(systemName: systemImage),
            selectedImage: UIImage(systemName: selectedSystemImage)
        )
        return navigationController
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
        tabBar.tintColor = UIColor(red: 0.91, green: 0.39, blue: 0.18, alpha: 1)
        tabBar.unselectedItemTintColor = .secondaryLabel

        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 0.94)
                : UIColor(red: 0.97, green: 0.96, blue: 0.95, alpha: 0.94)
        }
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
    }
}

final class FireMainNavigationController: UINavigationController,
    UIGestureRecognizerDelegate,
    UINavigationControllerDelegate
{
    private enum FullScreenPop {
        static let parallaxDistanceRatio: CGFloat = 0.28
        static let finishProgress: CGFloat = 0.34
        static let finishVelocityX: CGFloat = 720
        static let horizontalBias: CGFloat = 1.08
    }

    private let hidesNavigationBarAtRoot: Bool
    private lazy var popAnimator = FireMainPopAnimator(
        parallaxDistanceRatio: FullScreenPop.parallaxDistanceRatio
    )
    private var popInteractionController: UIPercentDrivenInteractiveTransition?
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

    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        if !viewControllers.isEmpty {
            setNavigationBarHidden(false, animated: animated)
        }
        super.pushViewController(viewController, animated: animated)
    }

    @objc private func handleFullScreenPopPan(_ gestureRecognizer: UIPanGestureRecognizer) {
        let translation = gestureRecognizer.translation(in: view)
        let progress = min(max(translation.x / max(view.bounds.width, 1), 0), 1)

        switch gestureRecognizer.state {
        case .began:
            popInteractionController = UIPercentDrivenInteractiveTransition()
            if popViewController(animated: true) == nil {
                popInteractionController = nil
            }
        case .changed:
            popInteractionController?.update(progress)
        case .ended:
            let velocityX = gestureRecognizer.velocity(in: view).x
            if shouldFinishFullScreenPop(progress: progress, velocityX: velocityX) {
                popInteractionController?.finish()
            } else {
                popInteractionController?.cancel()
            }
            popInteractionController = nil
        case .cancelled, .failed:
            popInteractionController?.cancel()
            popInteractionController = nil
        default:
            break
        }
    }

    func canBeginFullScreenPop(velocity: CGPoint) -> Bool {
        guard viewControllers.count > 1,
              transitionCoordinator == nil,
              velocity.x > 0 else {
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
    }

    func navigationController(
        _ navigationController: UINavigationController,
        animationControllerFor operation: UINavigationController.Operation,
        from fromVC: UIViewController,
        to toVC: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        operation == .pop ? popAnimator : nil
    }

    func navigationController(
        _ navigationController: UINavigationController,
        interactionControllerFor animationController: UIViewControllerAnimatedTransitioning
    ) -> UIViewControllerInteractiveTransitioning? {
        popInteractionController
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
}

private final class FireMainPopAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let duration: TimeInterval = 0.28
    private let parallaxDistanceRatio: CGFloat

    init(parallaxDistanceRatio: CGFloat) {
        self.parallaxDistanceRatio = parallaxDistanceRatio
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        duration
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let fromView = transitionContext.view(forKey: .from),
              let toView = transitionContext.view(forKey: .to),
              let toViewController = transitionContext.viewController(forKey: .to) else {
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            return
        }

        let containerView = transitionContext.containerView
        let width = max(containerView.bounds.width, 1)
        toView.frame = transitionContext.finalFrame(for: toViewController)
        toView.transform = CGAffineTransform(translationX: -width * parallaxDistanceRatio, y: 0)
        containerView.insertSubview(toView, belowSubview: fromView)

        let previousShadowOpacity = fromView.layer.shadowOpacity
        let previousShadowRadius = fromView.layer.shadowRadius
        let previousShadowOffset = fromView.layer.shadowOffset
        let previousShadowColor = fromView.layer.shadowColor
        fromView.layer.shadowColor = UIColor.black.cgColor
        fromView.layer.shadowOpacity = 0.18
        fromView.layer.shadowRadius = 12
        fromView.layer.shadowOffset = CGSize(width: -3, height: 0)

        UIView.animate(
            withDuration: transitionDuration(using: transitionContext),
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction],
            animations: {
                fromView.transform = CGAffineTransform(translationX: width, y: 0)
                toView.transform = .identity
            },
            completion: { _ in
                let cancelled = transitionContext.transitionWasCancelled
                fromView.transform = .identity
                toView.transform = .identity
                fromView.layer.shadowOpacity = previousShadowOpacity
                fromView.layer.shadowRadius = previousShadowRadius
                fromView.layer.shadowOffset = previousShadowOffset
                fromView.layer.shadowColor = previousShadowColor
                if cancelled {
                    toView.removeFromSuperview()
                }
                transitionContext.completeTransition(!cancelled)
            }
        )
    }
}

private struct FireProfileTabRootHost: View {
    let viewModel: FireAppViewModel
    @ObservedObject var navigationState: FireNavigationState
    @ObservedObject var profileViewModel: FireProfileViewModel
    @ObservedObject var topicDetailStore: FireTopicDetailStore

    var body: some View {
        FireProfileView(
            viewModel: viewModel,
            profileViewModel: profileViewModel,
            isActive: navigationState.selectedTab == 2
        )
        .environmentObject(navigationState)
        .environmentObject(topicDetailStore)
        .fireTopicRoutePresenter(topicRoutePresenter)
    }

    private var topicRoutePresenter: FireTopicRoutePresenter {
        FireTopicRoutePresenter { route in
            guard route.isTopicRoute else {
                viewModel.topicRouteLogger()?.debug(
                    "profile tab topic presenter ignored non-topic route \(route.diagnosticsSummary)"
                )
                return false
            }
            viewModel.topicRouteLogger()?.info("profile tab presenting topic route \(route.diagnosticsSummary)")
            navigationState.presentTopicRoute(route)
            return true
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
