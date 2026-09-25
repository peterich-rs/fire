import UIKit

/// Owns topic-detail navigation chrome:
/// - empty title while the in-feed header title is visible (before first pin)
/// - pinned, single-line truncated title after the header scrolls away; stays after first pin
/// - title consumes only leftover space between back and trailing actions (never shoves icons)
/// - right-side action cluster collapses to `...` once on first pin, then stays compact
///   unless the user expands it (auto-collapses after idle)
@MainActor
final class FireTopicDetailToolbarCoordinator {
    struct Actions {
        let onToggleSearch: () -> Void
        let onPresentTopicEditor: () -> Void
        let onPresentBookmarkEditor: () -> Void
        let onUpdateNotificationLevel: (FireTopicNotificationLevelOption) -> Void
    }

    static let autoCollapseDelay: TimeInterval = 3.0
    static let animationDuration: TimeInterval = 0.24

    private weak var viewController: UIViewController?
    private let actions: Actions

    private var state = FireTopicDetailToolbarState(
        title: "",
        shareURL: nil,
        isBookmarked: false,
        canWriteInteractions: false,
        canEditTopic: false,
        isPrivateMessageThread: false,
        currentNotificationLevel: .regular
    )

    private let actionsView = FireTopicDetailToolbarActionsView()
    private lazy var actionsBarItem = UIBarButtonItem(customView: actionsView)
    private let titleLabel = FireTopicDetailToolbarTitleLabel()
    private var isTitlePinned = false
    private var areActionsExpanded = true
    /// After the first pin-driven collapse, keep the compact chrome so scroll no longer
    /// thrash-expands/collapses the action cluster (perf + battery).
    private var prefersCompactActions = false
    private var autoCollapseWorkItem: DispatchWorkItem?
    private var appliedTitleText: String?
    private var appliedTitleVisible: Bool?
    private var appliedTrailing: FireTopicDetailToolbarActionsView.Configuration?

    init(
        viewController: UIViewController,
        actions: Actions
    ) {
        self.viewController = viewController
        self.actions = actions
        configureActionsView()
    }

    func configureNavigationItem(_ item: UINavigationItem) {
        item.largeTitleDisplayMode = .never
        // Leading slot is the system back button. Center is the title.
        // Trailing is the icon cluster.
        item.titleView = titleLabel
        item.rightBarButtonItem = actionsBarItem
        apply(to: item, animated: false)
    }

    func apply(state: FireTopicDetailToolbarState) {
        self.state = state
        guard let navigationItem = viewController?.navigationItem else { return }
        apply(to: navigationItem, animated: false)
    }

    /// Scroll-driven chrome updates from the feed surface.
    /// `isScrolling` is accepted for call-site stability but no longer drives chrome;
    /// after the one-time teaching collapse, only the user (or idle timer) changes expansion.
    func updateScrollChrome(isTitlePinned: Bool, isScrolling _: Bool) {
        let pinnedChanged = self.isTitlePinned != isTitlePinned
        self.isTitlePinned = isTitlePinned

        guard pinnedChanged else {
            // Ignore continuous scroll ticks — repeated spring animations were costly.
            return
        }

        if isTitlePinned {
            // First pin only: collapse once so the user learns `...` is tappable.
            // Afterwards stay compact unless the user expands manually.
            if !prefersCompactActions {
                prefersCompactActions = true
                setActionsExpanded(false, animated: true)
            }
        } else if !prefersCompactActions {
            // Only before the one-time teaching collapse may scroll restore the full cluster.
            cancelAutoCollapse()
            setActionsExpanded(true, animated: true)
        } else {
            // Compact mode sticks: no re-expand animation when returning to the header.
            cancelAutoCollapse()
        }
        updateTitleDisplay(animated: true)
    }

    private func configureActionsView() {
        actionsView.onSearch = { [weak self] in
            self?.noteUserInteraction()
            self?.actions.onToggleSearch()
        }
        actionsView.onShare = { [weak self] sourceView in
            guard let self, let shareURL = self.state.shareURL else { return }
            self.noteUserInteraction()
            self.presentShareSheet(url: shareURL, sourceView: sourceView)
        }
        actionsView.onExpand = { [weak self] in
            self?.setActionsExpanded(true, animated: true)
            self?.scheduleAutoCollapse()
        }
        actionsView.onNotificationMenuAction = { [weak self] in
            self?.noteUserInteraction()
        }
        actionsView.onSelectNotificationLevel = { [weak self] option in
            self?.noteUserInteraction()
            self?.actions.onUpdateNotificationLevel(option)
        }
        actionsView.onPresentTopicEditor = { [weak self] in
            self?.noteUserInteraction()
            self?.actions.onPresentTopicEditor()
        }
        actionsView.onPresentBookmarkEditor = { [weak self] in
            self?.noteUserInteraction()
            self?.actions.onPresentBookmarkEditor()
        }
    }

    private func apply(to item: UINavigationItem, animated: Bool) {
        item.largeTitleDisplayMode = .never
        if item.titleView !== titleLabel {
            item.titleView = titleLabel
        }
        if item.rightBarButtonItem !== actionsBarItem {
            item.rightBarButtonItem = actionsBarItem
        }

        // Before the one-time collapse, header-visible state keeps the full cluster open.
        // Afterward the compact `...` affordance sticks for the rest of the screen life.
        if !isTitlePinned, !prefersCompactActions {
            areActionsExpanded = true
            cancelAutoCollapse()
        }

        applyTrailingSlot(animated: animated)
        applyTitleSlot(animated: animated)
    }

    private func trailingConfiguration() -> FireTopicDetailToolbarActionsView.Configuration {
        .init(
            shareURLAvailable: state.shareURL != nil,
            showsNotification: !state.isPrivateMessageThread,
            isBookmarked: state.isBookmarked,
            canWriteInteractions: state.canWriteInteractions,
            canEditTopic: state.canEditTopic && !state.isPrivateMessageThread,
            currentNotificationLevel: state.currentNotificationLevel,
            isExpanded: areActionsExpanded,
            collapsesToOverflow: isTitlePinned || prefersCompactActions
        )
    }

    private func applyTitleSlot(animated: Bool) {
        let shouldShow = (isTitlePinned || prefersCompactActions) && !state.title.isEmpty
        let text = shouldShow ? state.title : ""
        guard appliedTitleText != text || appliedTitleVisible != shouldShow else { return }
        appliedTitleText = text
        appliedTitleVisible = shouldShow
        titleLabel.setTitle(text, visible: shouldShow, animated: animated)
    }

    private func applyTrailingSlot(animated: Bool) {
        let configuration = trailingConfiguration()
        guard appliedTrailing != configuration else { return }
        appliedTrailing = configuration
        actionsView.apply(configuration: configuration, animated: animated)
        refreshBarButtonLayout()
    }

    private func updateTitleDisplay(animated: Bool) {
        applyTitleSlot(animated: animated)
    }

    private func setActionsExpanded(_ expanded: Bool, animated: Bool) {
        guard areActionsExpanded != expanded else {
            if expanded, prefersCompactActions || isTitlePinned {
                scheduleAutoCollapse()
            }
            return
        }
        areActionsExpanded = expanded
        if !expanded {
            cancelAutoCollapse()
        }

        applyTrailingSlot(animated: animated)

        if expanded, prefersCompactActions || isTitlePinned {
            scheduleAutoCollapse()
        }
    }

    private func noteUserInteraction() {
        guard areActionsExpanded, prefersCompactActions || isTitlePinned else { return }
        scheduleAutoCollapse()
    }

    private func scheduleAutoCollapse() {
        cancelAutoCollapse()
        guard areActionsExpanded, prefersCompactActions || isTitlePinned else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.areActionsExpanded else { return }
            self.setActionsExpanded(false, animated: true)
        }
        autoCollapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoCollapseDelay, execute: workItem)
    }

    private func cancelAutoCollapse() {
        autoCollapseWorkItem?.cancel()
        autoCollapseWorkItem = nil
    }

    private func refreshBarButtonLayout() {
        actionsView.invalidateIntrinsicContentSize()
        // Re-assign so UINavigationBar rebuilds the item wrapper around the new bounds.
        viewController?.navigationItem.rightBarButtonItem = actionsBarItem
        if let bar = viewController?.navigationController?.navigationBar {
            UIView.animate(
                withDuration: Self.animationDuration,
                delay: 0,
                usingSpringWithDamping: 0.88,
                initialSpringVelocity: 0.2,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                bar.layoutIfNeeded()
            }
        }
    }

    private func presentShareSheet(url: URL, sourceView: UIView) {
        guard let viewController else { return }
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activityVC.popoverPresentationController?.sourceView = sourceView
        activityVC.popoverPresentationController?.sourceRect = sourceView.bounds
        viewController.present(activityVC, animated: true)
    }
}
