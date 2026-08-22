import UIKit

/// Discord-style channel message row for multi-user chat.
///
/// Layout:
/// ```
/// [avatar]  username · 12:30
///           rich cooked body…
///           :heart: 2  ·  3 条回复
/// ```
/// Avatars use `FireTopicListAvatarView` (Nuke/`FireRemoteImagePipeline`).
/// Body uses Rust `renderCookedHtml` → `FireRichTextUIView` (emoji via Nuke).
@MainActor
final class FireChatMessageCell: UITableViewCell {
    static let reuseID = "FireChatMessageCell"

    private let avatarView = FireTopicListAvatarView()
    private let headerStack = UIStackView()
    private let authorLabel = UILabel()
    private let timeLabel = UILabel()
    private let bodyView = FireRichTextUIView()
    private let metaLabel = UILabel()
    private let threadChip = UIButton(type: .system)
    private let contentColumn = UIStackView()

    private var contentTopExpanded: NSLayoutConstraint?
    private var contentTopCompact: NSLayoutConstraint?
    private var configuredMessageID: UInt64?

    var onThreadTap: (() -> Void)?
    var onProfileTap: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        avatarView.translatesAutoresizingMaskIntoConstraints = false

        authorLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        authorLabel.textColor = FireTheme.uiInk
        authorLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        timeLabel.font = .systemFont(ofSize: 12, weight: .regular)
        timeLabel.textColor = FireTheme.uiTertiaryInk
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)

        headerStack.axis = .horizontal
        headerStack.alignment = .firstBaseline
        headerStack.spacing = 8
        headerStack.addArrangedSubview(authorLabel)
        headerStack.addArrangedSubview(timeLabel)
        let headerSpacer = UIView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        headerStack.addArrangedSubview(headerSpacer)

        bodyView.translatesAutoresizingMaskIntoConstraints = false
        bodyView.backgroundColor = .clear
        bodyView.isEditable = false
        bodyView.isScrollEnabled = false
        bodyView.isSelectable = true
        bodyView.textContainerInset = .zero
        bodyView.textContainer.lineFragmentPadding = 0
        bodyView.dataDetectorTypes = []
        bodyView.linkTextAttributes = [
            .foregroundColor: FireTheme.uiAccent,
        ]
        // Avoid nested scroll fights inside the table.
        bodyView.setContentCompressionResistancePriority(.required, for: .vertical)

        metaLabel.font = .systemFont(ofSize: 12, weight: .medium)
        metaLabel.textColor = FireTheme.uiSubtleInk
        metaLabel.numberOfLines = 2

        var chipConfig = UIButton.Configuration.plain()
        chipConfig.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
        chipConfig.baseForegroundColor = FireTheme.uiAccent
        chipConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 12, weight: .semibold)
            return outgoing
        }
        threadChip.configuration = chipConfig
        threadChip.backgroundColor = FireTheme.uiAccentSoft
        threadChip.layer.cornerRadius = 8
        threadChip.layer.cornerCurve = .continuous
        threadChip.contentHorizontalAlignment = .leading
        threadChip.addTarget(self, action: #selector(threadTapped), for: .touchUpInside)
        threadChip.isHidden = true

        contentColumn.axis = .vertical
        contentColumn.alignment = .fill
        contentColumn.spacing = 3
        contentColumn.translatesAutoresizingMaskIntoConstraints = false
        contentColumn.addArrangedSubview(headerStack)
        contentColumn.addArrangedSubview(bodyView)
        contentColumn.addArrangedSubview(metaLabel)
        contentColumn.addArrangedSubview(threadChip)

        contentView.addSubview(avatarView)
        contentView.addSubview(contentColumn)

        avatarView.isUserInteractionEnabled = true
        authorLabel.isUserInteractionEnabled = true
        avatarView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(profileTapped)))
        authorLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(profileTapped)))

        let topExpanded = contentColumn.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10)
        let topCompact = contentColumn.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2)
        contentTopExpanded = topExpanded
        contentTopCompact = topCompact

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            avatarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            avatarView.widthAnchor.constraint(equalToConstant: 40),
            avatarView.heightAnchor.constraint(equalToConstant: 40),

            // Fixed text column gutter so compact rows align under full rows (Discord).
            contentColumn.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 64),
            contentColumn.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            topExpanded,
            contentColumn.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
        bodyView.attributedText = nil
        bodyView.renderedContentID = nil
        configuredMessageID = nil
        onThreadTap = nil
        onProfileTap = nil
    }

    func configure(
        message: ChatMessageState,
        groupedWithPrevious: Bool,
        baseURLString: String?
    ) {
        let username = message.user?.username ?? "用户"
        let baseURL = baseURLString ?? "https://linux.do"
        authorLabel.text = username
        timeLabel.text = Self.formatTime(message.createdAt)

        let contentID = "chat:\(message.id):\(message.cooked.hashValue):\(message.message.hashValue)"
        if configuredMessageID != message.id || bodyView.renderedContentID != contentID {
            let attributed = FireChatRichText.attributedBody(
                message: message,
                baseURLString: baseURL
            )
            bodyView.renderedContentID = contentID
            bodyView.attributedText = attributed
            configuredMessageID = message.id
        }

        var metaParts: [String] = []
        if message.edited { metaParts.append("已编辑") }
        if message.pinned { metaParts.append("置顶") }
        if !message.reactions.isEmpty {
            metaParts.append(
                message.reactions
                    .map { ":\($0.emoji): \($0.count)" }
                    .joined(separator: "  ")
            )
        }
        metaLabel.text = metaParts.joined(separator: " · ")
        metaLabel.isHidden = metaParts.isEmpty

        if let replyCount = message.thread?.replyCount, replyCount > 0 {
            threadChip.isHidden = false
            var config = threadChip.configuration ?? .plain()
            config.title = "\(replyCount) 条回复"
            threadChip.configuration = config
        } else {
            threadChip.isHidden = true
        }

        applyGrouping(groupedWithPrevious)
        if !groupedWithPrevious {
            avatarView.configure(
                username: username,
                avatarTemplate: message.user?.avatarTemplate,
                baseURLString: baseURL
            )
        } else {
            avatarView.prepareForReuse()
        }
    }

    private func applyGrouping(_ grouped: Bool) {
        headerStack.isHidden = grouped
        avatarView.isHidden = grouped
        contentTopExpanded?.isActive = !grouped
        contentTopCompact?.isActive = grouped
    }

    @objc private func threadTapped() {
        onThreadTap?()
    }

    @objc private func profileTapped() {
        onProfileTap?()
    }

    private static func formatTime(_ value: String?) -> String {
        guard let value, let date = FireChatTime.parse(value) else { return "" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Cooked HTML → attributed body

enum FireChatRichText {
    private static let cache = NSCache<NSString, NSAttributedString>()

    static func attributedBody(
        message: ChatMessageState,
        baseURLString: String
    ) -> NSAttributedString {
        let cacheKey =
            "\(message.id)|\(message.cooked.hashValue)|\(message.message.hashValue)|\(message.isDeleted)"
            as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let baseFont = UIFont.systemFont(ofSize: 15, weight: .regular)
        let textColor = FireTheme.uiInk
        let accent = FireTheme.uiAccent

        if message.isDeleted {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.italicSystemFont(ofSize: 15),
                .foregroundColor: FireTheme.uiTertiaryInk,
            ]
            let value = NSAttributedString(string: "消息已删除", attributes: attrs)
            cache.setObject(value, forKey: cacheKey)
            return value
        }

        let cooked = message.cooked.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cooked.isEmpty {
            let document = renderCookedHtml(rawHtml: cooked, baseUrl: baseURLString)
            let content = FireRenderBlockNodeBuilder.build(document: document)
            if !content.nodes.isEmpty {
                let value = FireRichTextAttributedStringBuilder.build(
                    from: content.nodes,
                    baseFont: baseFont,
                    textColor: textColor,
                    accentColor: accent
                )
                if value.length > 0 {
                    cache.setObject(value, forKey: cacheKey)
                    return value
                }
            }
            // Fall through to plain text when cook produced empty nodes.
            if !document.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let value = NSAttributedString(
                    string: document.plainText,
                    attributes: [
                        .font: baseFont,
                        .foregroundColor: textColor,
                    ]
                )
                cache.setObject(value, forKey: cacheKey)
                return value
            }
        }

        let plain = message.message.isEmpty
            ? (message.uploads.isEmpty ? message.previewText : "[图片/附件]")
            : message.message
        let value = NSAttributedString(
            string: plain,
            attributes: [
                .font: baseFont,
                .foregroundColor: textColor,
            ]
        )
        cache.setObject(value, forKey: cacheKey)
        return value
    }
}

enum FireChatTime {
    static func parse(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) {
            return date
        }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: value)
    }

    /// Group consecutive messages from the same author within this window.
    static let groupInterval: TimeInterval = 7 * 60

    static func shouldGroup(previous: ChatMessageState?, current: ChatMessageState) -> Bool {
        guard let previous,
              previous.user?.id != nil,
              previous.user?.id == current.user?.id,
              let prevTime = previous.createdAt.flatMap(parse),
              let currTime = current.createdAt.flatMap(parse)
        else {
            return false
        }
        return abs(currTime.timeIntervalSince(prevTime)) <= groupInterval
    }
}
