import UIKit

final class FirePrivateMessagesPickerCell: UICollectionViewCell {
    private let segmentedControl = UISegmentedControl(items: ["收件箱", "已发送"])
    private var onSelectKind: ((TopicListKindState) -> Void)?
    private var isConfiguring = false

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
        onSelectKind = nil
    }

    func configure(
        selectedKind: TopicListKindState,
        onSelectKind: @escaping (TopicListKindState) -> Void
    ) {
        isConfiguring = true
        segmentedControl.selectedSegmentIndex = selectedKind == .privateMessagesInbox ? 0 : 1
        isConfiguring = false
        self.onSelectKind = onSelectKind
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 12,
            leading: 16,
            bottom: 8,
            trailing: 16
        )

        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.addAction(UIAction { [weak self] _ in
            guard let self, !self.isConfiguring else { return }
            let kind: TopicListKindState =
                self.segmentedControl.selectedSegmentIndex == 0
                    ? .privateMessagesInbox
                    : .privateMessagesSent
            self.onSelectKind?(kind)
        }, for: .valueChanged)
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(segmentedControl)
        NSLayoutConstraint.activate([
            segmentedControl.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            segmentedControl.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            segmentedControl.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            segmentedControl.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }
}

final class FirePrivateMessageListCell: UICollectionViewCell {
    private let avatarView = FireTopicListAvatarView()
    private let titleLabel = UILabel()
    private let chipLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let excerptLabel = UILabel()
    private let metricsLabel = UILabel()

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
        avatarView.prepareForReuse()
        titleLabel.text = nil
        subtitleLabel.text = nil
        excerptLabel.text = nil
        metricsLabel.text = nil
    }

    func configureMissing() {
        titleLabel.text = nil
        subtitleLabel.text = nil
        excerptLabel.text = nil
        metricsLabel.text = nil
        avatarView.prepareForReuse()
    }

    func configure(
        row: TopicRowState,
        participants: [TopicParticipantState],
        currentUsername: String?,
        baseURLString: String
    ) {
        let displayParticipants = Self.filteredParticipants(
            participants,
            currentUsername: currentUsername
        )
        let firstParticipant = displayParticipants.first
        let username = firstParticipant?.username ?? firstParticipant?.name ?? "pm"
        let subtitle = Self.participantSubtitle(for: displayParticipants)
        let excerpt = row.excerptText?.trimmingCharacters(in: .whitespacesAndNewlines)

        titleLabel.text = row.topic.title.ifEmpty("私信会话")
        subtitleLabel.text = subtitle
        excerptLabel.text = excerpt?.isEmpty == false ? excerpt : nil
        excerptLabel.isHidden = excerptLabel.text == nil
        metricsLabel.text = Self.metricsText(row: row)
        avatarView.configure(
            username: username,
            avatarTemplate: firstParticipant?.avatarTemplate,
            baseURLString: baseURLString
        )

        isAccessibilityElement = true
        accessibilityTraits = [.button]
        accessibilityLabel = [
            titleLabel.text,
            subtitleLabel.text,
            excerptLabel.text,
            metricsLabel.text,
        ]
        .compactMap { $0 }
        .joined(separator: "，")
        accessibilityHint = "双击查看私信话题"
    }

    private static func filteredParticipants(
        _ participants: [TopicParticipantState],
        currentUsername: String?
    ) -> [TopicParticipantState] {
        let current = currentUsername?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let current, !current.isEmpty else {
            return participants
        }
        return participants.filter {
            $0.username?.caseInsensitiveCompare(current) != .orderedSame
        }
    }

    private static func participantSubtitle(for participants: [TopicParticipantState]) -> String {
        let labels = participants.compactMap { participant in
            let preferred = (participant.name ?? "").ifEmpty(
                participant.username ?? "用户 \(participant.userId)"
            )
            let trimmed = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard !labels.isEmpty else {
            return "私信会话"
        }
        return labels.joined(separator: "、")
    }

    private static func metricsText(row: TopicRowState) -> String {
        var parts = ["\(row.topic.replyCount) 回复"]
        if let timestamp = FireTopicPresentation.compactTimestamp(unixMs: row.activityTimestampUnixMs) {
            parts.append(timestamp)
        }
        return parts.joined(separator: " · ")
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 10,
            leading: 16,
            bottom: 10,
            trailing: 16
        )

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.widthAnchor.constraint(equalToConstant: 34).isActive = true
        avatarView.heightAnchor.constraint(equalToConstant: 34).isActive = true

        titleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2

        chipLabel.text = "私信"
        chipLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
        chipLabel.adjustsFontForContentSizeCategory = true
        chipLabel.textColor = FireTopicListPalette.accent
        chipLabel.backgroundColor = FireTopicListPalette.accent.withAlphaComponent(0.13)
        chipLabel.textAlignment = .center
        chipLabel.layer.cornerRadius = 5
        chipLabel.layer.masksToBounds = true
        chipLabel.setContentHuggingPriority(.required, for: .horizontal)

        subtitleLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 1

        excerptLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        excerptLabel.adjustsFontForContentSizeCategory = true
        excerptLabel.textColor = .secondaryLabel
        excerptLabel.numberOfLines = 3

        metricsLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
        metricsLabel.adjustsFontForContentSizeCategory = true
        metricsLabel.textColor = .tertiaryLabel
        metricsLabel.numberOfLines = 1

        let metaStack = UIStackView(arrangedSubviews: [chipLabel, subtitleLabel])
        metaStack.axis = .horizontal
        metaStack.alignment = .center
        metaStack.spacing = 6

        let textStack = UIStackView(arrangedSubviews: [
            titleLabel,
            metaStack,
            excerptLabel,
            metricsLabel,
        ])
        textStack.axis = .vertical
        textStack.spacing = 6

        let rootStack = UIStackView(arrangedSubviews: [avatarView, textStack])
        rootStack.axis = .horizontal
        rootStack.alignment = .top
        rootStack.spacing = 12
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            chipLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 20),
            chipLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 34),
        ])
    }
}
