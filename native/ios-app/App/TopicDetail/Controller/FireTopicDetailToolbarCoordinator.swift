import UIKit

@MainActor
final class FireTopicDetailToolbarCoordinator {
    struct Actions {
        let onToggleSearch: () -> Void
        let onPresentTopicEditor: () -> Void
        let onPresentBookmarkEditor: () -> Void
        let onUpdateNotificationLevel: (FireTopicNotificationLevelOption) -> Void
        let onChangeViewMode: (FireTopicDetailViewMode) -> Void
    }

    private weak var viewController: UIViewController?
    private let actions: Actions
    private var state = FireTopicDetailToolbarState(
        title: "话题",
        shareURL: nil,
        viewMode: .conversation,
        isBookmarked: false,
        canWriteInteractions: false,
        canEditTopic: false,
        isPrivateMessageThread: false,
        currentNotificationLevel: .regular
    )

    init(
        viewController: UIViewController,
        actions: Actions
    ) {
        self.viewController = viewController
        self.actions = actions
    }

    func configureNavigationItem(_ item: UINavigationItem) {
        item.largeTitleDisplayMode = .never
        apply(to: item)
    }

    func apply(state: FireTopicDetailToolbarState) {
        self.state = state
        guard let navigationItem = viewController?.navigationItem else { return }
        apply(to: navigationItem)
    }

    private func apply(to item: UINavigationItem) {
        item.title = state.title
        item.rightBarButtonItems = buildRightBarButtonItems()
    }

    private func buildRightBarButtonItems() -> [UIBarButtonItem] {
        var items: [UIBarButtonItem] = []

        let searchItem = UIBarButtonItem(
            image: UIImage(systemName: "magnifyingglass"),
            primaryAction: UIAction { [actions] _ in
                actions.onToggleSearch()
            }
        )
        searchItem.accessibilityLabel = "搜索已加载帖子"
        items.append(searchItem)

        if let shareURL = state.shareURL {
            var shareButton: UIBarButtonItem!
            shareButton = UIBarButtonItem(
                image: UIImage(systemName: "square.and.arrow.up"),
                primaryAction: UIAction { [weak self] _ in
                    self?.presentShareSheet(url: shareURL, anchor: shareButton)
                }
            )
            shareButton.accessibilityLabel = "分享话题"
            items.append(shareButton)
        }

        let viewModeItem = UIBarButtonItem(
            title: state.viewMode.title,
            menu: buildViewModeMenu()
        )
        viewModeItem.accessibilityLabel = "切换话题视图"
        items.append(viewModeItem)

        if !state.isPrivateMessageThread {
            let notificationItem = UIBarButtonItem(
                image: UIImage(systemName: state.currentNotificationLevel.systemImageName),
                menu: buildNotificationLevelMenu()
            )
            notificationItem.accessibilityLabel = "通知设置：\(state.currentNotificationLevel.title)"
            notificationItem.isEnabled = state.canWriteInteractions
            items.append(notificationItem)
        }

        let menuItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: buildEllipsisMenu()
        )
        menuItem.accessibilityLabel = "更多操作"
        items.append(menuItem)

        return items.reversed()
    }

    private func buildEllipsisMenu() -> UIMenu {
        var sections: [UIMenu] = []

        if state.canEditTopic && !state.isPrivateMessageThread {
            let editAction = UIAction(
                title: "编辑话题",
                image: UIImage(systemName: "pencil")
            ) { [actions] _ in
                actions.onPresentTopicEditor()
            }
            sections.append(UIMenu(options: .displayInline, children: [editAction]))
        }

        let bookmarkAction = UIAction(
            title: state.isBookmarked ? "编辑书签" : "添加书签",
            image: UIImage(systemName: state.isBookmarked ? "bookmark.fill" : "bookmark"),
            attributes: state.canWriteInteractions ? [] : .disabled
        ) { [actions] _ in
            actions.onPresentBookmarkEditor()
        }
        sections.append(UIMenu(options: .displayInline, children: [bookmarkAction]))

        return UIMenu(title: "", children: sections)
    }

    private func buildNotificationLevelMenu() -> UIMenu {
        let notificationActions = FireTopicNotificationLevelOption.allCases.map { option in
            UIAction(
                title: option.title,
                image: option == state.currentNotificationLevel ? UIImage(systemName: "checkmark") : nil,
                attributes: state.canWriteInteractions ? [] : .disabled
            ) { [actions] _ in
                actions.onUpdateNotificationLevel(option)
            }
        }
        return UIMenu(title: "通知设置", options: .displayInline, children: notificationActions)
    }

    private func buildViewModeMenu() -> UIMenu {
        let modeActions = FireTopicDetailViewMode.allCases.map { mode in
            UIAction(
                title: mode.title,
                image: mode == state.viewMode ? UIImage(systemName: "checkmark") : nil
            ) { [actions] _ in
                actions.onChangeViewMode(mode)
            }
        }
        return UIMenu(title: "话题视图", options: .displayInline, children: modeActions)
    }

    private func presentShareSheet(url: URL, anchor: UIBarButtonItem?) {
        guard let viewController else { return }
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activityVC.popoverPresentationController?.barButtonItem = anchor
        viewController.present(activityVC, animated: true)
    }
}
