import SwiftUI
import UIKit

extension FireHomeViewController {
    func contextMenuConfiguration(
        for item: FireHomeCollectionItem
    ) -> UIContextMenuConfiguration? {
        guard case let .topic(topicID) = item,
              let row = homeFeedStore.topicRow(for: topicID)
        else {
            return nil
        }
        let shareURL = row.fireTopicURL(baseURL: baseURLString)
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: self?.topicMenuActions(row: row, shareURL: shareURL) ?? [])
        }
    }

    func topicMenuActions(
        row: FireTopicRowPresentation,
        shareURL: URL
    ) -> [UIAction] {
        [
            UIAction(title: "打开话题", image: UIImage(systemName: "arrow.up.right")) { [weak self] _ in
                self?.presentRoute(.topic(row: row))
            },
            UIAction(
                title: row.topic.bookmarkId == nil ? "添加书签" : "编辑书签",
                image: UIImage(systemName: row.topic.bookmarkId == nil ? "bookmark" : "bookmark.fill")
            ) { [weak self] _ in
                self?.presentBookmarkEditor(for: row)
            },
            UIAction(title: "分享话题", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                self?.presentShareSheet(url: shareURL)
            },
            UIAction(title: "复制链接", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                UIPasteboard.general.string = shareURL.absoluteString
                self?.showToast("已复制链接", style: .success)
            },
            UIAction(title: "静音话题", image: UIImage(systemName: "bell.slash")) { [weak self] _ in
                self?.muteTopic(row)
            },
        ]
    }

    func consumePendingRouteIfVisible(_ route: FireAppRoute?) {
        guard navigationState.selectedTab == 0, let route else {
            return
        }
        switch route {
        case .topic, .profile, .badge, .search:
            break
        case .notifications, .profileTab:
            return
        }
        presentRoute(route)
        navigationState.pendingRoute = nil
    }

    func consumePendingSearchQuery(_ query: String?) {
        guard navigationState.selectedTab == 0,
              let query = query?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return
        }
        presentSearch(initialQuery: query.isEmpty ? nil : query)
        navigationState.pendingSearchQuery = nil
    }

    func presentRoute(_ route: FireAppRoute) {
        let logger = appViewModel.topicRouteLogger()
        logger?.debug("home controller present route requested \(route.diagnosticsSummary)")
        if case .search(let query) = route {
            logger?.debug("home controller routing search query_present=\(query != nil)")
            let trimmedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmedQuery, !trimmedQuery.isEmpty {
                presentSearch(initialQuery: trimmedQuery)
            } else {
                presentSearch(initialQuery: nil)
            }
            navigationState.pendingSearchQuery = nil
            return
        }
        if topicRoutePresenter.present(route) {
            logger?.debug("home controller route handled by topic presenter \(route.diagnosticsSummary)")
            return
        }
        if route.presentsAsSecondaryPage {
            logger?.debug("home controller routing secondary route \(route.diagnosticsSummary)")
            FireAppRouteControllerFactory.presentSecondaryRoute(
                route,
                viewModel: appViewModel,
                topicDetailStore: topicDetailStore
            )
            return
        }
        logger?.debug("home controller ignored non-secondary route \(route.diagnosticsSummary)")
    }

    func presentSearch(initialQuery: String?) {
        let presenter = FireTopicRoutePresenter.appRoot(
            navigationState: navigationState,
            logger: appViewModel.topicRouteLogger()
        )
        let controller = FireSearchViewController(
            viewModel: appViewModel,
            searchStore: searchStore,
            topicDetailStore: topicDetailStore,
            initialQuery: initialQuery,
            topicRoutePresenter: presenter,
            fallbackRoutePresenter: { [weak self] route in
                self?.presentRoute(route)
            }
        )
        FireRootCoordinator.presentSecondary(controller)
    }

    @objc func createTopicButtonTapped() {
        presentCreateTopicComposer()
    }

    @objc func searchButtonTapped() {
        presentSearch(initialQuery: nil)
    }

    func presentCreateTopicComposer() {
        let composer = FireComposerViewController(
            viewModel: appViewModel,
            route: FireComposerRoute(kind: .createTopic),
            initialCategoryID: homeFeedStore.selectedHomeCategoryId,
            initialTags: homeFeedStore.selectedHomeTags,
            onSubmissionNotice: { [weak self] message in
                self?.showToast(message, style: .info)
            }
        )
        let navigationController = UINavigationController(rootViewController: composer)
        navigationController.modalPresentationStyle = .fullScreen
        composerController = navigationController
        present(navigationController, animated: true)
    }

    @objc func categoryDrawerButtonTapped() {
        presentCategoryDrawer()
    }

    func presentCategoryDrawer() {
        FireHomeCategoryDrawerPresenter.present(from: self, homeFeedStore: homeFeedStore)
    }

    func presentSubcategoryPanel() {
        let scope = homeFeedStore.scopePresentation
        guard let parent = scope.selectedParent else {
            presentCategoryDrawer()
            return
        }
        let children = FireHomeScopePresentation.children(
            of: parent.id,
            in: homeFeedStore.allCategories
        )
        guard !children.isEmpty else {
            presentCategoryDrawer()
            return
        }
        let panel = FireHomeSubcategoryPanelController(
            homeFeedStore: homeFeedStore,
            parent: parent,
            children: children
        )
        let navigationController = UINavigationController(rootViewController: panel)
        navigationController.navigationBar.tintColor = FireTheme.uiAccent
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        }
        present(navigationController, animated: true)
    }

    func presentBookmarkEditor(for row: FireTopicRowPresentation) {
        let context = row.fireBookmarkEditorContext()
        let recoveryOriginURL = row.fireTopicURL(baseURL: baseURLString)
        let rootView = FireBookmarkEditorSheet(
            context: context,
            onSave: { [weak self] name, reminderAt in
                try await self?.saveBookmark(
                    context: context,
                    name: name,
                    reminderAt: reminderAt,
                    recoveryOriginURL: recoveryOriginURL
                )
            },
            onDelete: context.bookmarkID.map { bookmarkID in
                { [weak self] in
                    try await self?.deleteBookmark(
                        bookmarkID: bookmarkID,
                        recoveryOriginURL: recoveryOriginURL,
                        showSuccessToast: false
                    )
                }
            }
        )
        let controller = UIHostingController(rootView: rootView)
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(controller, animated: true)
    }

    func saveBookmark(
        context: FireBookmarkEditorContext,
        name: String?,
        reminderAt: String?,
        recoveryOriginURL: URL
    ) async throws {
        if let bookmarkID = context.bookmarkID {
            try await appViewModel.topicInteraction.updateBookmark(
                bookmarkID: bookmarkID,
                name: name,
                reminderAt: reminderAt,
                recoveryOriginURL: recoveryOriginURL
            )
        } else {
            _ = try await appViewModel.topicInteraction.createBookmark(
                bookmarkableID: context.bookmarkableID,
                bookmarkableType: context.bookmarkableType,
                name: name,
                reminderAt: reminderAt,
                recoveryOriginURL: recoveryOriginURL
            )
        }
        await homeFeedStore.refreshTopicsAsync()
    }

    func deleteBookmarkFromAction(for row: FireTopicRowPresentation) {
        guard let bookmarkID = row.topic.bookmarkId else { return }
        let recoveryOriginURL = row.fireTopicURL(baseURL: baseURLString)
        refreshTask = Task { [weak self] in
            do {
                try await self?.deleteBookmark(
                    bookmarkID: bookmarkID,
                    recoveryOriginURL: recoveryOriginURL,
                    showSuccessToast: true
                )
            } catch {
                self?.showToast(error.localizedDescription, style: .error)
            }
        }
    }

    func deleteBookmark(
        bookmarkID: UInt64,
        recoveryOriginURL: URL,
        showSuccessToast: Bool
    ) async throws {
        try await appViewModel.topicInteraction.deleteBookmark(
            bookmarkID: bookmarkID,
            recoveryOriginURL: recoveryOriginURL
        )
        await homeFeedStore.refreshTopicsAsync()
        if showSuccessToast {
            showToast("已删除书签", style: .success)
        }
    }

    func muteTopic(_ row: FireTopicRowPresentation) {
        refreshTask = Task { [weak self] in
            do {
                try await self?.appViewModel.topicInteraction.setTopicNotificationLevel(
                    topicID: row.topic.id,
                    notificationLevel: FireTopicNotificationLevelOption.muted.rawValue,
                    recoveryOriginURL: row.fireTopicURL(baseURL: self?.baseURLString ?? "https://linux.do")
                )
                self?.showToast("已静音话题", style: .success)
            } catch {
                self?.showToast(error.localizedDescription, style: .error)
            }
        }
    }

    func presentShareSheet(url: URL) {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(
                x: view.bounds.midX,
                y: view.safeAreaInsets.top + 24,
                width: 1,
                height: 1
            )
        }
        present(controller, animated: true)
    }

    func showToast(_ message: String, style: FireTopicListToastView.Style) {
        toastDismissTask?.cancel()
        toastView?.removeFromSuperview()
        toastView = nil
        FireUIKitToast.show(message, style: FireUIKitToast.Style(style), in: view)
    }

    func syncOfflineBanner(animated: Bool) {
        let shouldShow = homeFeedStore.isOffline
        let changes = {
            self.offlineBannerView.alpha = shouldShow ? 1 : 0
            self.offlineBannerView.transform = shouldShow
                ? .identity
                : CGAffineTransform(translationX: 0, y: -8)
        }

        if shouldShow {
            offlineBannerView.isHidden = false
        }

        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self else { return }
            if !shouldShow {
                self.offlineBannerView.isHidden = true
            }
        }

        if animated {
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                options: [.curveEaseOut],
                animations: changes,
                completion: completion
            )
        } else {
            changes()
            completion(true)
        }
    }
}
