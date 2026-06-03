import UIKit

/// Configures the navigation bar and provides toolbar actions for the topic-detail page.
///
/// Translates detail state into `UIBarButtonItem`s and handles presentation of
/// share sheets, bookmark editors, notification-level menus, and topic editors.
///
/// The coordinator intentionally holds a weak reference back to the owning
/// view controller so it can present modals without creating retain cycles.
@MainActor
final class FireTopicDetailToolbarCoordinator {

    // MARK: - Weak Reference

    private weak var viewController: FireTopicDetailViewController?
    private let viewModel: FireAppViewModel
    private let row: FireTopicRowPresentation

    // MARK: - State Snapshot

    private var detail: TopicDetailState?

    // MARK: - Init

    init(
        viewController: FireTopicDetailViewController,
        viewModel: FireAppViewModel,
        row: FireTopicRowPresentation
    ) {
        self.viewController = viewController
        self.viewModel = viewModel
        self.row = row
    }

    // MARK: - Initial Setup

    func configureNavigationItem(_ item: UINavigationItem) {
        item.title = "话题"
        item.largeTitleDisplayMode = .never
        item.rightBarButtonItems = buildRightBarButtonItems()
    }

    // MARK: - Live Update

    func update(detail: TopicDetailState?) {
        self.detail = detail
        viewController?.navigationItem.rightBarButtonItems = buildRightBarButtonItems()
    }

    // MARK: - Bar Button Item Construction

    private func buildRightBarButtonItems() -> [UIBarButtonItem] {
        var items: [UIBarButtonItem] = []

        // Ellipsis menu (bookmark, notification level, edit topic)
        let menuButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            style: .plain,
            target: self,
            action: #selector(handleEllipsisMenu)
        )
        menuButton.accessibilityLabel = "更多操作"
        items.append(menuButton)

        // Share link
        if let shareURL = topicShareURL {
            let shareButton = UIBarButtonItem(
                image: UIImage(systemName: "square.and.arrow.up"),
                style: .plain,
                target: nil,
                action: nil
            )
            shareButton.accessibilityLabel = "分享话题"
            shareButton.primaryAction = UIAction { [weak self, shareURL] _ in
                self?.presentShareSheet(url: shareURL)
            }
            items.append(shareButton)
        }

        return items.reversed()
    }

    // MARK: - Actions

    @objc private func handleEllipsisMenu() {
        guard let vc = viewController else { return }

        var actions: [UIAction] = []

        // Edit Topic (if allowed and not private message)
        let canEdit = detail?.details.canEdit == true && !isPrivateMessageThread
        if canEdit {
            actions.append(UIAction(
                title: "编辑话题",
                image: UIImage(systemName: "pencil")
            ) { [weak self] _ in
                self?.presentTopicEditor()
            })
        }

        // Bookmark
        let isBookmarked = detail?.bookmarked == true
        let bookmarkImage = UIImage(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
        let bookmarkTitle = isBookmarked ? "编辑书签" : "添加书签"
        actions.append(UIAction(
            title: bookmarkTitle,
            image: bookmarkImage,
            attributes: viewModel.canStartAuthenticatedMutation ? [] : .disabled
        ) { [weak self] _ in
            self?.presentBookmarkEditor()
        })

        // Notification level submenu
        if !isPrivateMessageThread {
            let notificationActions = FireTopicNotificationLevelOption.allCases.map { option in
                let isCurrent = option == currentNotificationLevel
                return UIAction(
                    title: option.title,
                    image: isCurrent ? UIImage(systemName: "checkmark") : nil,
                    attributes: viewModel.canStartAuthenticatedMutation ? [] : .disabled
                ) { [weak self] _ in
                    self?.updateNotificationLevel(option)
                }
            }
            actions.append(contentsOf: notificationActions)
        }

        let menu = UIMenu(title: "", children: actions)
        let menuButton = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), menu: menu)
        // Present via the existing right bar button item rather than re-configuring
        // the nav item; just show the menu directly from the tapped item.
        _ = menuButton
        // Re-assign the bar button item with the composed menu
        let menuItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: UIMenu(title: "", children: actions)
        )
        menuItem.accessibilityLabel = "更多操作"
        // Replace the first item (ellipsis) with the fresh menu
        if var items = vc.navigationItem.rightBarButtonItems, !items.isEmpty {
            items[0] = menuItem
            vc.navigationItem.rightBarButtonItems = items
        }
    }

    // MARK: - Share Sheet

    private func presentShareSheet(url: URL) {
        guard let vc = viewController else { return }
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activityVC.popoverPresentationController {
            popover.barButtonItem = vc.navigationItem.rightBarButtonItems?.first
        }
        vc.present(activityVC, animated: true)
    }

    // MARK: - Bookmark

    private func presentBookmarkEditor() {
        // SwiftUI bookmark editor is presented via the notification center; this
        // pattern will be replaced with a native UIKit coordinator in Task 6.
        // For now, we post a notification that the existing SwiftUI subscription picks up
        // — but since we are on a UIKit controller there is no SwiftUI overlay.
        // TODO(Task 6): Wire FireTopicDetailModalRouter bookmark flow.
    }

    // MARK: - Topic Editor

    private func presentTopicEditor() {
        // TODO(Task 6): Replace with UIKit-owned modal.
    }

    // MARK: - Notification Level

    private func updateNotificationLevel(_ option: FireTopicNotificationLevelOption) {
        guard let vc = viewController else { return }
        let topicId = row.topic.id
        let detail = detail
        let slug = detail?.slug ?? row.topic.slug
        let recoveryURL = viewModel.cloudflareRecoveryTopicURL(
            topicId: topicId,
            topicSlug: slug.isEmpty ? nil : slug
        )

        Task {
            do {
                try await viewModel.setTopicNotificationLevel(
                    topicID: topicId,
                    notificationLevel: option.rawValue,
                    recoveryOriginURL: recoveryURL
                )
                await vc.loadTopicDetail(force: true)
            } catch {
                // Show error inline — modal router in Task 6.
                _ = error
            }
        }
    }

    // MARK: - Derived State

    private var topicShareURL: URL? {
        let baseURLString: String = {
            let trimmed = viewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "https://linux.do" : trimmed
        }()
        let slug = (detail?.slug ?? row.topic.slug)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let topicId = row.topic.id
        let path = slug.isEmpty ? "topic-\(topicId)" : slug
        return URL(string: "\(baseURLString)/t/\(path)/\(topicId)")
    }

    private var isPrivateMessageThread: Bool {
        FireTopicPresentation.isPrivateMessageArchetype(detail?.archetype)
    }

    private var currentNotificationLevel: FireTopicNotificationLevelOption {
        FireTopicNotificationLevelOption(rawValue: Int32(detail?.details.notificationLevel ?? 1)) ?? .regular
    }
}
