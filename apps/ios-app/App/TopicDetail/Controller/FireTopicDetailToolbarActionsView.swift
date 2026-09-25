import UIKit

final class FireTopicDetailToolbarActionsView: UIView {
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
