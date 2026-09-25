import UIKit

final class FireTopicListTopicCell: UICollectionViewCell {
    private let outerStack = UIStackView()
    private let metaStack = UIStackView()
    private let bookmarkNameLabel = UILabel()
    private let reminderLabel = UILabel()
    private let moreButton = UIButton(type: .system)
    private let avatarView = FireTopicListAvatarView()
    private let titleLabel = UILabel()
    private let chipStack = UIStackView()
    private let usernameLabel = UILabel()
    private let timestampLabel = UILabel()
    private let replyMetric = FireTopicListMetricView(kind: .replies)
    private let viewsMetric = FireTopicListMetricView(kind: .views)
    private let likesMetric = FireTopicListMetricView(kind: .likes)
    private var onEditBookmark: (() -> Void)?
    private var onDeleteBookmark: (() -> Void)?
    var onAvatarTap: ((String) -> Void)?
    private var avatarUsername: String?
    private var boundTopicID: UInt64?
    private var pendingViewSurgePulse = false
    private var pendingHeartBalloon = false
    private var pendingHeartTint: UIColor = FireTheme.uiAccent

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        FireTopicListMetricEffectCoordinator.shared.untrack(self)
        boundTopicID = nil
        pendingViewSurgePulse = false
        pendingHeartBalloon = false
        avatarView.prepareForReuse()
        replyMetric.prepareForReuse()
        viewsMetric.prepareForReuse()
        likesMetric.prepareForReuse()
        onEditBookmark = nil
        onDeleteBookmark = nil
        onAvatarTap = nil
        avatarUsername = nil
        moreButton.menu = nil
    }

    private func configureMetrics(for row: FireTopicRowPresentation) {
        let created = row.createdTimestampUnixMs
        boundTopicID = row.topic.id

        let replyEmphasis = FireTopicListMetricRanking.emphasis(
            kind: .replies,
            value: row.topic.replyCount,
            createdTimestampUnixMs: created
        )
        let viewsEmphasis = FireTopicListMetricRanking.emphasis(
            kind: .views,
            value: row.topic.views,
            createdTimestampUnixMs: created
        )
        let likesEmphasis = FireTopicListMetricRanking.emphasis(
            kind: .likes,
            value: row.topic.likeCount,
            createdTimestampUnixMs: created
        )

        // Static chrome always updates immediately — only micro-animations wait.
        replyMetric.configure(value: row.topic.replyCount, emphasis: replyEmphasis)
        viewsMetric.configure(
            value: row.topic.views,
            emphasis: viewsEmphasis,
            surgeAccessorySymbol: viewsEmphasis == .surge
                ? FireTopicListMetricRanking.surgeAccessorySymbol(createdTimestampUnixMs: created)
                : nil,
            animateEffects: false
        )
        likesMetric.configure(
            value: row.topic.likeCount,
            emphasis: likesEmphasis,
            animateEffects: false
        )

        pendingViewSurgePulse = viewsEmphasis == .surge
            && !FireTopicListMetricEffectCoordinator.shared.hasPlayed(
                .viewSurgePulse,
                topicID: row.topic.id
            )
        pendingHeartBalloon = likesEmphasis == .high
            && !FireTopicListMetricEffectCoordinator.shared.hasPlayed(
                .heartBalloon,
                topicID: row.topic.id
            )
        pendingHeartTint = FireTopicListMetricView.tint(
            kind: .likes,
            emphasis: likesEmphasis
        )

        FireTopicListMetricEffectCoordinator.shared.track(self)
    }

    /// Invoked by the effect coordinator once the host list is settled.
    func playPendingMetricEffectsIfNeeded() {
        guard let topicID = boundTopicID else { return }
        guard FireTopicListMetricEffectCoordinator.shared.isSettled else { return }
        guard window != nil else { return }

        if pendingViewSurgePulse {
            pendingViewSurgePulse = false
            if FireTopicListMetricEffectCoordinator.shared.claim(.viewSurgePulse, topicID: topicID) {
                viewsMetric.playSurgePulse()
            }
        }

        if pendingHeartBalloon {
            pendingHeartBalloon = false
            if FireTopicListMetricEffectCoordinator.shared.claim(.heartBalloon, topicID: topicID) {
                likesMetric.playHeartBalloons(tint: pendingHeartTint)
            }
        }
    }

    func configureMissing() {
        FireTopicListMetricEffectCoordinator.shared.untrack(self)
        boundTopicID = nil
        pendingViewSurgePulse = false
        pendingHeartBalloon = false
        titleLabel.text = nil
        chipStack.arrangedSubviews.forEach { view in
            chipStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        metaStack.isHidden = true
        avatarView.prepareForReuse()
        replyMetric.prepareForReuse()
        viewsMetric.prepareForReuse()
        likesMetric.prepareForReuse()
    }

    func configure(
        row: FireTopicRowPresentation,
        category: FireTopicCategoryPresentation?,
        baseURLString: String,
        onEditBookmark: @escaping () -> Void,
        onDeleteBookmark: @escaping () -> Void
    ) {
        let username = Self.displayUsername(for: row)
        self.onEditBookmark = onEditBookmark
        self.onDeleteBookmark = onDeleteBookmark

        titleLabel.text = row.topic.title
        usernameLabel.text = username
        timestampLabel.text = FireTopicPresentation.compactTimestamp(unixMs: row.createdTimestampUnixMs)
        configureMetrics(for: row)
        avatarUsername = row.originalPosterUsername ?? username
        avatarView.configure(
            username: username,
            avatarTemplate: row.originalPosterAvatarTemplate,
            baseURLString: baseURLString
        )
        avatarView.isUserInteractionEnabled = true
        if avatarView.gestureRecognizers?.isEmpty != false {
            avatarView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleAvatarTap)))
        }
        configureMeta(row: row)
        configureChips(row: row, category: category)
        configureMenu(canDelete: row.topic.bookmarkId != nil)

        isAccessibilityElement = true
        accessibilityTraits = [.button]
        accessibilityLabel = Self.accessibilitySummary(row: row, category: category, username: username)
        accessibilityHint = "双击查看话题详情"
    }

    @objc private func handleAvatarTap() {
        guard let avatarUsername, !avatarUsername.isEmpty else { return }
        onAvatarTap?(avatarUsername)
    }

    private func configureMeta(row: FireTopicRowPresentation) {
        let bookmarkName = row.topic.bookmarkName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let reminder = FireTopicPresentation.compactTimestamp(row.topic.bookmarkReminderAt)
        bookmarkNameLabel.text = bookmarkName.isEmpty ? nil : "书签：\(bookmarkName)"
        reminderLabel.text = reminder.map { "提醒：\($0)" }
        bookmarkNameLabel.isHidden = bookmarkNameLabel.text == nil
        reminderLabel.isHidden = reminderLabel.text == nil
        moreButton.isHidden = row.topic.bookmarkId == nil
        metaStack.isHidden = bookmarkNameLabel.isHidden && reminderLabel.isHidden && moreButton.isHidden
    }

    private func configureMenu(canDelete: Bool) {
        guard canDelete else {
            moreButton.menu = nil
            return
        }
        moreButton.showsMenuAsPrimaryAction = true
        moreButton.menu = UIMenu(children: [
            UIAction(title: "编辑", image: UIImage(systemName: "pencil")) { [weak self] _ in
                self?.onEditBookmark?()
            },
            UIAction(
                title: "删除",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.onDeleteBookmark?()
            },
        ])
    }

    private func configureChips(
        row: FireTopicRowPresentation,
        category: FireTopicCategoryPresentation?
    ) {
        chipStack.arrangedSubviews.forEach { view in
            chipStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if let category {
            let categoryTint = UIColor(fireHex: category.colorHex) ?? FireTopicListPalette.accent
            chipStack.addArrangedSubview(
                FireTopicListChipLabel(
                    text: category.displayName,
                    textColor: categoryTint,
                    backgroundColor: FireTopicListPalette.categoryChipBackground(accent: categoryTint)
                )
            )
        }

        for tagName in row.tagNames.prefix(3) {
            chipStack.addArrangedSubview(
                FireTopicListChipLabel(
                    text: "#\(tagName)",
                    textColor: FireTopicListPalette.tagChipForeground,
                    backgroundColor: FireTopicListPalette.tagChipBackground
                )
            )
        }

        if row.isPinned {
            chipStack.addArrangedSubview(FireTopicListIconChip(systemImage: "pin.fill", tintColor: .systemOrange))
        }
        if row.hasAcceptedAnswer {
            chipStack.addArrangedSubview(
                FireTopicListIconChip(systemImage: "checkmark.circle.fill", tintColor: .systemGreen)
            )
        }
        if row.hasUnreadPosts {
            chipStack.addArrangedSubview(FireTopicListUnreadDot())
        }

        let chipCount = chipStack.arrangedSubviews.count
        if chipCount > 0 {
            let spacer = UIView()
            spacer.isAccessibilityElement = false
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            chipStack.addArrangedSubview(spacer)
        }
        chipStack.isHidden = chipCount == 0
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        // Allow high-like heart balloons to rise a few points above the metric chip.
        clipsToBounds = false
        contentView.clipsToBounds = false
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 10,
            leading: 16,
            bottom: 10,
            trailing: 16
        )

        outerStack.axis = .vertical
        outerStack.spacing = 8
        outerStack.clipsToBounds = false
        outerStack.translatesAutoresizingMaskIntoConstraints = false

        metaStack.axis = .horizontal
        metaStack.alignment = .center
        metaStack.spacing = 8

        [bookmarkNameLabel, reminderLabel].forEach { label in
            label.font = UIFont.preferredFont(forTextStyle: .caption1)
            label.adjustsFontForContentSizeCategory = true
            label.textColor = .secondaryLabel
            label.numberOfLines = 1
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        moreButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        moreButton.tintColor = .tertiaryLabel
        moreButton.accessibilityLabel = "书签操作"
        moreButton.setContentHuggingPriority(.required, for: .horizontal)
        moreButton.widthAnchor.constraint(equalToConstant: 32).isActive = true
        moreButton.heightAnchor.constraint(equalToConstant: 32).isActive = true

        metaStack.addArrangedSubview(bookmarkNameLabel)
        metaStack.addArrangedSubview(reminderLabel)
        metaStack.addArrangedSubview(UIView())
        metaStack.addArrangedSubview(moreButton)

        let rowStack = UIStackView()
        rowStack.axis = .horizontal
        rowStack.alignment = .top
        rowStack.spacing = 12
        rowStack.clipsToBounds = false

        let bodyStack = UIStackView()
        bodyStack.axis = .vertical
        bodyStack.alignment = .fill
        bodyStack.spacing = 7
        bodyStack.clipsToBounds = false

        titleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2

        chipStack.axis = .horizontal
        chipStack.alignment = .center
        chipStack.spacing = 6

        let bylineStack = UIStackView()
        bylineStack.axis = .horizontal
        bylineStack.alignment = .center
        bylineStack.spacing = 6

        usernameLabel.font = UIFont.preferredFont(forTextStyle: .caption1).withWeight(.medium)
        usernameLabel.adjustsFontForContentSizeCategory = true
        usernameLabel.textColor = FireTopicListPalette.subtleInk
        usernameLabel.numberOfLines = 1

        timestampLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        timestampLabel.adjustsFontForContentSizeCategory = true
        timestampLabel.textColor = FireTopicListPalette.tertiaryInk
        timestampLabel.numberOfLines = 1

        bylineStack.addArrangedSubview(usernameLabel)
        bylineStack.addArrangedSubview(timestampLabel)
        bylineStack.addArrangedSubview(UIView())

        // Reply + views stay left-clustered; likes hug the trailing edge for balance.
        let leadingMetrics = UIStackView(arrangedSubviews: [replyMetric, viewsMetric])
        leadingMetrics.axis = .horizontal
        leadingMetrics.alignment = .center
        leadingMetrics.spacing = 14
        leadingMetrics.clipsToBounds = false

        let metricSpacer = UIView()
        metricSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        metricSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        likesMetric.setContentHuggingPriority(.required, for: .horizontal)
        likesMetric.setContentCompressionResistancePriority(.required, for: .horizontal)

        let metricStack = UIStackView(arrangedSubviews: [leadingMetrics, metricSpacer, likesMetric])
        metricStack.axis = .horizontal
        metricStack.alignment = .center
        metricStack.spacing = 8
        metricStack.clipsToBounds = false

        bodyStack.addArrangedSubview(titleLabel)
        bodyStack.addArrangedSubview(chipStack)
        bodyStack.addArrangedSubview(bylineStack)
        bodyStack.addArrangedSubview(metricStack)

        rowStack.addArrangedSubview(avatarView)
        rowStack.addArrangedSubview(bodyStack)

        outerStack.addArrangedSubview(metaStack)
        outerStack.addArrangedSubview(rowStack)

        contentView.addSubview(outerStack)
        // Self-sizing list cells briefly apply UIView-Encapsulated-Layout-Height (often ~52).
        // Keep the bottom edge one step below required so that temporary height does not fight
        // fixed metric icon sizes and spam unsatisfiable-constraint logs.
        let bottom = outerStack.bottomAnchor.constraint(
            equalTo: contentView.layoutMarginsGuide.bottomAnchor
        )
        bottom.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 36),
            avatarView.heightAnchor.constraint(equalToConstant: 36),
            outerStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            outerStack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            bottom,
        ])
    }

    private static func displayUsername(for row: FireTopicRowPresentation) -> String {
        row.originalPosterUsername
            ?? row.topic.lastPosterUsername
            ?? fallbackPresentationUsername(for: row)
            ?? row.topic.posters.first.map { "User \($0.userId)" }
            ?? "?"
    }

    private static func fallbackPresentationUsername(for row: FireTopicRowPresentation) -> String? {
        guard let candidate = row.lastPosterUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
              !candidate.isEmpty
        else {
            return nil
        }
        return candidate.localizedCaseInsensitiveContains("poster") ? nil : candidate
    }

    private static func accessibilitySummary(
        row: FireTopicRowPresentation,
        category: FireTopicCategoryPresentation?,
        username: String
    ) -> String {
        var parts = [row.topic.title]
        if let category {
            parts.append(category.displayName)
        }
        if !username.isEmpty, username != "?" {
            parts.append(username)
        }
        parts.append("\(row.topic.replyCount) 回复")
        parts.append("\(row.topic.views) 浏览")
        if row.topic.likeCount > 0 {
            parts.append("\(row.topic.likeCount) 赞")
        }
        if row.isPinned {
            parts.append("置顶")
        }
        if row.hasAcceptedAnswer {
            parts.append("已有采纳答案")
        }
        if row.hasUnreadPosts {
            parts.append("有未读回复")
        }
        return parts.joined(separator: "，")
    }
}
