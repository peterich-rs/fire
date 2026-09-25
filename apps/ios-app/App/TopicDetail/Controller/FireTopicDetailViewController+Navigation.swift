import UIKit

@MainActor
extension FireTopicDetailViewController {
    func updateDismissButtonIfNeeded() {
        let isRootPresentedTopic =
            navigationController?.presentingViewController != nil
            && navigationController?.viewControllers.count == 1
        if isRootPresentedTopic {
            let dismissAction = UIAction { [weak self] _ in
                self?.dismissPresentedTopicDetail()
            }
            let dismissItem = UIBarButtonItem(
                title: "返回",
                image: UIImage(systemName: "chevron.backward"),
                primaryAction: dismissAction
            )
            dismissItem.accessibilityLabel = "返回"
            navigationItem.leftBarButtonItem = dismissItem
        } else {
            navigationItem.leftBarButtonItem = nil
        }
    }

    func dismissPresentedTopicDetail() {
        navigationController?.dismiss(animated: true)
    }

    var needsPresentedRootEdgeDismissGesture: Bool {
        (navigationController?.viewControllers.count ?? 0) <= 1
            && (navigationController?.presentingViewController != nil || presentingViewController != nil)
    }

    var canNavigateBackFromTopicDetail: Bool {
        if let navigationController {
            return navigationController.viewControllers.count > 1
                || navigationController.presentingViewController != nil
        }
        return presentingViewController != nil
    }

    func updateBackGestureAvailability() {
        let usesMainNavigationController = navigationController is FireMainNavigationController
        navigationController?.interactivePopGestureRecognizer?.isEnabled =
            !usesMainNavigationController && (navigationController?.viewControllers.count ?? 0) > 1
        pageBackEdgePanGestureRecognizer.isEnabled =
            !usesMainNavigationController && canNavigateBackFromTopicDetail
    }

    @objc func handlePageBackEdgePan(_ gestureRecognizer: UIScreenEdgePanGestureRecognizer) {
        guard gestureRecognizer.state == .ended,
              canNavigateBackFromTopicDetail,
              navigationController?.transitionCoordinator == nil else {
            return
        }
        let translation = gestureRecognizer.translation(in: view)
        let velocity = gestureRecognizer.velocity(in: view)
        let horizontalDistance = max(translation.x, 0)
        let horizontalVelocity = max(velocity.x, 0)
        guard horizontalDistance > 72 || horizontalVelocity > 420,
              max(abs(translation.x), abs(velocity.x)) > max(abs(translation.y), abs(velocity.y)) else {
            return
        }
        navigateBackFromTopicDetail()
    }

    func navigateBackFromTopicDetail() {
        if let navigationController, navigationController.viewControllers.count > 1 {
            navigationController.popViewController(animated: true)
        } else if let navigationController {
            navigationController.dismiss(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pageBackEdgePanGestureRecognizer,
              let panGesture = gestureRecognizer as? UIScreenEdgePanGestureRecognizer else {
            return true
        }
        guard canNavigateBackFromTopicDetail,
              navigationController?.transitionCoordinator == nil else {
            return false
        }
        let velocity = panGesture.velocity(in: view)
        return velocity.x >= 0 && abs(velocity.x) >= abs(velocity.y)
    }

    func configureNavigationAppearance() {
        // Opaque chrome so dark images scrolling underneath cannot tint the bar black
        // in light mode (translucent material samples feed content).
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = FireTheme.uiCanvas
        appearance.shadowColor = FireTheme.uiDivider
        appearance.titleTextAttributes = [
            .foregroundColor: FireTheme.uiInk,
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: FireTheme.uiInk,
        ]

        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.compactAppearance = appearance
        navigationController?.navigationBar.isTranslucent = false
        navigationController?.navigationBar.tintColor = FireTheme.uiAccent
        navigationController?.navigationBar.barTintColor = FireTheme.uiCanvas
        view.backgroundColor = FireTheme.uiCanvas
        view.tintColor = FireTheme.uiAccent
    }
}
