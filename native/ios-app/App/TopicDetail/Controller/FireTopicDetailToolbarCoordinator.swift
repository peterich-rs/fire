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

    fileprivate static let autoCollapseDelay: TimeInterval = 3.0
    fileprivate static let animationDuration: TimeInterval = 0.24

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

        actionsView.apply(
            configuration: .init(
                shareURLAvailable: state.shareURL != nil,
                showsNotification: !state.isPrivateMessageThread,
                isBookmarked: state.isBookmarked,
                canWriteInteractions: state.canWriteInteractions,
                canEditTopic: state.canEditTopic && !state.isPrivateMessageThread,
                currentNotificationLevel: state.currentNotificationLevel,
                isExpanded: areActionsExpanded,
                collapsesToOverflow: isTitlePinned || prefersCompactActions
            ),
            animated: animated
        )
        updateTitleDisplay(animated: animated)
        refreshBarButtonLayout()
    }

    private func updateTitleDisplay(animated: Bool) {
        // After the first pin, keep the nav title visible so chrome stays calm on scroll-back.
        let shouldShow = (isTitlePinned || prefersCompactActions) && !state.title.isEmpty
        titleLabel.setTitle(
            shouldShow ? state.title : "",
            visible: shouldShow,
            animated: animated
        )
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

        actionsView.apply(
            configuration: .init(
                shareURLAvailable: state.shareURL != nil,
                showsNotification: !state.isPrivateMessageThread,
                isBookmarked: state.isBookmarked,
                canWriteInteractions: state.canWriteInteractions,
                canEditTopic: state.canEditTopic && !state.isPrivateMessageThread,
                currentNotificationLevel: state.currentNotificationLevel,
                isExpanded: areActionsExpanded,
                collapsesToOverflow: isTitlePinned || prefersCompactActions
            ),
            animated: animated
        )
        refreshBarButtonLayout()

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

// MARK: - Title label

private final class FireTopicDetailToolbarTitleLabel: UIView {
    private let label = UILabel()
    private var isTitleVisible = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        // Title must yield horizontal space to trailing actions. Publishing a
        // content-sized width lets long titles compete with (and shove) icons.
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = FireTheme.uiInk
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.numberOfLines = 1
        label.alpha = 0
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: FireTopicDetailToolbarTitleMetrics.minimumHeight),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setTitle(_ text: String, visible: Bool, animated: Bool) {
        isTitleVisible = visible
        let updates = {
            self.label.text = text
            self.label.alpha = visible ? 1 : 0
            self.isAccessibilityElement = visible
            self.accessibilityLabel = visible ? "话题标题：\(text)" : nil
            self.invalidateIntrinsicContentSize()
        }
        if animated {
            UIView.animate(
                withDuration: FireTopicDetailToolbarCoordinator.animationDuration,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction],
                animations: updates
            )
        } else {
            updates()
        }
    }

    override var intrinsicContentSize: CGSize {
        FireTopicDetailToolbarTitleMetrics.preferredIntrinsicSize(
            isVisible: isTitleVisible,
            labelHeight: label.intrinsicContentSize.height
        )
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        // Accept whatever width the navigation bar assigns after reserving
        // left/right items; height stays compact for the single-line title.
        let intrinsic = intrinsicContentSize
        let width = size.width > 0 ? size.width : intrinsic.width
        return CGSize(width: width, height: intrinsic.height)
    }
}

// MARK: - Actions cluster

private final class FireTopicDetailToolbarActionsView: UIView {
    struct Configuration: Equatable {
        var shareURLAvailable: Bool
        var showsNotification: Bool
        var isBookmarked: Bool
        var canWriteInteractions: Bool
        var canEditTopic: Bool
        var currentNotificationLevel: FireTopicNotificationLevelOption
        var isExpanded: Bool
        /// When false, the cluster stays fully expanded (header still visible).
        var collapsesToOverflow: Bool
    }

    private static let barHeight: CGFloat = 36
    private static let buttonSide: CGFloat = 32
    private static let horizontalInset: CGFloat = 6
    private static let interItemSpacing: CGFloat = 2

    var onSearch: (() -> Void)?
    var onShare: ((UIView) -> Void)?
    var onExpand: (() -> Void)?
    var onNotificationMenuAction: (() -> Void)?
    var onSelectNotificationLevel: ((FireTopicNotificationLevelOption) -> Void)?
    var onPresentTopicEditor: (() -> Void)?
    var onPresentBookmarkEditor: (() -> Void)?

    private let backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let stackView = UIStackView()
    private let searchButton = UIButton(type: .system)
    private let shareButton = UIButton(type: .system)
    private let notificationButton = UIButton(type: .system)
    private let editButton = UIButton(type: .system)
    private let bookmarkButton = UIButton(type: .system)
    /// Collapsed-only control that expands the action cluster.
    private let overflowButton = UIButton(type: .system)

    private var configuration = Configuration(
        shareURLAvailable: false,
        showsNotification: true,
        isBookmarked: false,
        canWriteInteractions: false,
        canEditTopic: false,
        currentNotificationLevel: .regular,
        isExpanded: true,
        collapsesToOverflow: false
    )

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Keep the root view frame-driven for UIBarButtonItem; only subviews use AL.
        translatesAutoresizingMaskIntoConstraints = true
        autoresizingMask = [.flexibleLeftMargin, .flexibleHeight]
        // Actions own a fixed capsule width. Never let the titleView compress us.
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        configureHierarchy()
        apply(configuration: configuration, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(configuration: Configuration, animated: Bool) {
        self.configuration = configuration
        rebuildNotificationControl()

        // Expanded: flat action icons (search/share/bell/edit/bookmark), no overflow.
        // Collapsed: only `...`, which expands the cluster inline.
        let showCluster = configuration.isExpanded || !configuration.collapsesToOverflow
        let showShare = showCluster && configuration.shareURLAvailable
        let showNotification = showCluster && configuration.showsNotification
        let showEdit = showCluster && configuration.canEditTopic
        let showBookmark = showCluster
        let showOverflow = !showCluster
        let visibleCount = visibleButtonCount(
            showCluster: showCluster,
            showShare: showShare,
            showNotification: showNotification,
            showEdit: showEdit,
            showBookmark: showBookmark
        )
        let targetWidth = contentWidth(visibleButtonCount: visibleCount)

        let updates = {
            self.setArranged(self.searchButton, visible: showCluster)
            self.setArranged(self.shareButton, visible: showShare)
            self.setArranged(self.notificationButton, visible: showNotification)
            self.setArranged(self.editButton, visible: showEdit)
            self.updateBookmarkButton(visible: showBookmark)
            self.setArranged(self.overflowButton, visible: showOverflow)
            self.setContentWidth(targetWidth)
            self.layoutIfNeeded()
        }

        if animated {
            UIView.animate(
                withDuration: FireTopicDetailToolbarCoordinator.animationDuration,
                delay: 0,
                usingSpringWithDamping: 0.88,
                initialSpringVelocity: 0.25,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: updates
            )
        } else {
            updates()
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: bounds.width > 0 ? bounds.width : contentWidth(visibleButtonCount: 1), height: Self.barHeight)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        intrinsicContentSize
    }

    private func configureHierarchy() {
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.clipsToBounds = true
        backgroundView.layer.cornerRadius = Self.barHeight / 2
        backgroundView.layer.cornerCurve = .continuous
        // Keep a portable material fill. `UIGlassEffect` is only in newer SDKs and
        // breaks CI builds that compile against older Xcode toolchains.
        backgroundView.effect = UIBlurEffect(style: .systemChromeMaterial)

        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = Self.interItemSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        // Hug content; width is owned by `setContentWidth`, not by stretching the stack.
        stackView.setContentHuggingPriority(.required, for: .horizontal)
        stackView.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(backgroundView)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Leading + intrinsic stack width only. Do not pin trailing to the
            // bar-button wrapper — UINavigationBar may temporarily keep an old
            // autoresizing width while we animate bounds, and a trailing pin would
            // fight the fixed button widths.
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalInset),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        configureIconButton(searchButton, systemName: "magnifyingglass", accessibilityLabel: "搜索已加载帖子")
        searchButton.addAction(UIAction { [weak self] _ in
            self?.onSearch?()
        }, for: .touchUpInside)

        configureIconButton(shareButton, systemName: "square.and.arrow.up", accessibilityLabel: "分享话题")
        shareButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onShare?(self.shareButton)
        }, for: .touchUpInside)

        configureIconButton(
            notificationButton,
            systemName: configuration.currentNotificationLevel.systemImageName,
            accessibilityLabel: notificationAccessibilityLabel(
                for: configuration.currentNotificationLevel
            )
        )
        // One-tap cycle through levels — no menu popup.
        notificationButton.addAction(UIAction { [weak self] _ in
            self?.cycleNotificationLevel()
        }, for: .touchUpInside)

        configureIconButton(editButton, systemName: "pencil", accessibilityLabel: "编辑话题")
        editButton.addAction(UIAction { [weak self] _ in
            self?.onPresentTopicEditor?()
        }, for: .touchUpInside)

        configureIconButton(bookmarkButton, systemName: "bookmark", accessibilityLabel: "添加书签")
        bookmarkButton.addAction(UIAction { [weak self] _ in
            self?.onPresentBookmarkEditor?()
        }, for: .touchUpInside)

        configureIconButton(overflowButton, systemName: "ellipsis.circle", accessibilityLabel: "展开话题操作")
        overflowButton.addAction(UIAction { [weak self] _ in
            self?.onExpand?()
        }, for: .touchUpInside)

        [searchButton, shareButton, notificationButton, editButton, bookmarkButton, overflowButton].forEach { button in
            stackView.addArrangedSubview(button)
            button.translatesAutoresizingMaskIntoConstraints = false
            // Fixed icon slots; required is safe because outer width always matches
            // the number of currently visible slots.
            let width = button.widthAnchor.constraint(equalToConstant: Self.buttonSide)
            let height = button.heightAnchor.constraint(equalToConstant: Self.buttonSide)
            width.isActive = true
            height.isActive = true
        }
    }

    private func configureIconButton(
        _ button: UIButton,
        systemName: String,
        accessibilityLabel: String
    ) {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: systemName)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 15,
            weight: .semibold
        )
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        configuration.baseForegroundColor = FireTheme.uiInk
        button.configuration = configuration
        button.accessibilityLabel = accessibilityLabel
    }

    private func setArranged(_ button: UIButton, visible: Bool) {
        button.isHidden = !visible
        button.alpha = visible ? 1 : 0
        button.isAccessibilityElement = visible
    }

    private func updateBookmarkButton(visible: Bool) {
        let symbolName = configuration.isBookmarked ? "bookmark.fill" : "bookmark"
        applySymbol(bookmarkButton, systemName: symbolName)
        bookmarkButton.accessibilityLabel = configuration.isBookmarked ? "编辑书签" : "添加书签"
        bookmarkButton.isEnabled = configuration.canWriteInteractions
        setArranged(bookmarkButton, visible: visible)
    }

    private func applySymbol(_ button: UIButton, systemName: String) {
        var configuration = button.configuration ?? .plain()
        configuration.image = UIImage(systemName: systemName)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 15,
            weight: .semibold
        )
        configuration.baseForegroundColor = FireTheme.uiInk
        button.configuration = configuration
    }

    private func visibleButtonCount(
        showCluster: Bool,
        showShare: Bool,
        showNotification: Bool,
        showEdit: Bool,
        showBookmark: Bool
    ) -> Int {
        if !showCluster {
            return 1 // overflow only
        }
        var count = 1 // search
        if showShare { count += 1 }
        if showNotification { count += 1 }
        if showEdit { count += 1 }
        if showBookmark { count += 1 }
        return count
    }

    private func contentWidth(visibleButtonCount: Int) -> CGFloat {
        let count = CGFloat(max(visibleButtonCount, 1))
        return Self.horizontalInset * 2
            + count * Self.buttonSide
            + max(0, count - 1) * Self.interItemSpacing
    }

    private func setContentWidth(_ width: CGFloat) {
        let size = CGSize(width: width, height: Self.barHeight)
        // UINavigationBar reads the custom view's bounds through an autoresizing
        // wrapper. Updating bounds/frame keeps that wrapper aligned with content.
        bounds = CGRect(origin: .zero, size: size)
        frame = CGRect(origin: frame.origin, size: size)
        invalidateIntrinsicContentSize()
    }

    private func rebuildNotificationControl() {
        guard configuration.showsNotification else { return }
        notificationButton.showsMenuAsPrimaryAction = false
        notificationButton.menu = nil
        notificationButton.isEnabled = configuration.canWriteInteractions
        notificationButton.accessibilityLabel = notificationAccessibilityLabel(
            for: configuration.currentNotificationLevel
        )
        applySymbol(notificationButton, systemName: configuration.currentNotificationLevel.systemImageName)
    }

    private func cycleNotificationLevel() {
        guard configuration.canWriteInteractions else { return }
        let next = configuration.currentNotificationLevel.nextCycledLevel
        // Optimistic glyph update so the tap feels immediate; chrome refresh will
        // reconcile from server state after the write completes.
        configuration.currentNotificationLevel = next
        applySymbol(notificationButton, systemName: next.systemImageName)
        notificationButton.accessibilityLabel = notificationAccessibilityLabel(for: next)
        onNotificationMenuAction?()
        onSelectNotificationLevel?(next)
    }

    private func notificationAccessibilityLabel(
        for level: FireTopicNotificationLevelOption
    ) -> String {
        "通知设置：\(level.title)，点击切换"
    }
}

// MARK: - Scroll metrics

enum FireTopicDetailToolbarChromeMetrics {
    /// Approximate distance from the header cell top to below its title band.
    static let headerTitleBandHeight: CGFloat = 52

    static func isTitlePinned(
        headerFrame: CGRect?,
        visibleTop: CGFloat
    ) -> Bool {
        if let headerFrame {
            return headerFrame.minY + headerTitleBandHeight <= visibleTop + 0.5
        }
        return visibleTop > 24
    }
}

enum FireTopicDetailToolbarTitleMetrics {
    static let minimumHeight: CGFloat = 24

    /// Title views must not publish a content-sized width.
    ///
    /// Publishing the text width (even capped) makes `UINavigationBar` treat the
    /// title as a fixed peer of the trailing actions, so long titles shove icons
    /// toward — or past — the screen edge. Request expanded width instead; the
    /// bar assigns leftover space between back and actions, and the label
    /// truncates inside those bounds.
    static func preferredIntrinsicSize(
        isVisible: Bool,
        labelHeight: CGFloat
    ) -> CGSize {
        let height = max(labelHeight, minimumHeight)
        guard isVisible else {
            return CGSize(width: UIView.noIntrinsicMetric, height: height)
        }
        return CGSize(
            width: UIView.layoutFittingExpandedSize.width,
            height: height
        )
    }
}
