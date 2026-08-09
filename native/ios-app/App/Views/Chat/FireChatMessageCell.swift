import UIKit

/// Discord-style channel message row for multi-user chat.
///
/// Layout:
/// ```
/// [avatar]  username · 12:30
///           message body…
///           :heart: 2  ·  3 条回复
/// ```
/// Consecutive messages from the same author within a few minutes collapse the
/// avatar/header into a compact gutter so the stream reads like a channel log.
@MainActor
final class FireChatMessageCell: UITableViewCell {
    static let reuseID = "FireChatMessageCell"

    private let avatarView = UIImageView()
    private let avatarPlaceholder = UILabel()
    private let headerStack = UIStackView()
    private let authorLabel = UILabel()
    private let timeLabel = UILabel()
    private let bodyLabel = UILabel()
    private let metaLabel = UILabel()
    private let threadChip = UIButton(type: .system)
    private let contentColumn = UIStackView()

    private var avatarLeading: NSLayoutConstraint?
    private var avatarWidth: NSLayoutConstraint?
    private var avatarHeight: NSLayoutConstraint?
    private var contentTopToAvatar: NSLayoutConstraint?
    private var contentTopToContent: NSLayoutConstraint?
    private var avatarLoadToken = UUID()

    var onThreadTap: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = 20
        avatarView.layer.cornerCurve = .continuous
        avatarView.backgroundColor = FireTheme.uiSurfaceSecondary

        avatarPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        avatarPlaceholder.font = .systemFont(ofSize: 14, weight: .semibold)
        avatarPlaceholder.textColor = FireTheme.uiSubtleInk
        avatarPlaceholder.textAlignment = .center
        avatarView.addSubview(avatarPlaceholder)

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

        bodyLabel.font = .systemFont(ofSize: 15, weight: .regular)
        bodyLabel.textColor = FireTheme.uiInk
        bodyLabel.numberOfLines = 0

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
        contentColumn.alignment = .leading
        contentColumn.spacing = 3
        contentColumn.translatesAutoresizingMaskIntoConstraints = false
        contentColumn.addArrangedSubview(headerStack)
        contentColumn.addArrangedSubview(bodyLabel)
        contentColumn.addArrangedSubview(metaLabel)
        contentColumn.addArrangedSubview(threadChip)

        contentView.addSubview(avatarView)
        contentView.addSubview(contentColumn)

        let leading = avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12)
        let width = avatarView.widthAnchor.constraint(equalToConstant: 40)
        let height = avatarView.heightAnchor.constraint(equalToConstant: 40)
        let topToAvatar = contentColumn.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10)
        let topCompact = contentColumn.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2)
        avatarLeading = leading
        avatarWidth = width
        avatarHeight = height
        contentTopToAvatar = topToAvatar
        contentTopToContent = topCompact

        NSLayoutConstraint.activate([
            leading,
            avatarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            width,
            height,

            avatarPlaceholder.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            avatarPlaceholder.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),

            // Fixed text column gutter so compact rows align under full rows (Discord).
            contentColumn.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 64),
            contentColumn.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            topToAvatar,
            contentColumn.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarLoadToken = UUID()
        avatarView.image = nil
        avatarPlaceholder.text = nil
        onThreadTap = nil
    }

    func configure(
        message: ChatMessageState,
        groupedWithPrevious: Bool,
        baseURLString: String?
    ) {
        let username = message.user?.username ?? "用户"
        authorLabel.text = username
        timeLabel.text = Self.formatTime(message.createdAt)

        if message.isDeleted {
            bodyLabel.text = "消息已删除"
            bodyLabel.textColor = FireTheme.uiTertiaryInk
            bodyLabel.font = .italicSystemFont(ofSize: 15)
        } else if message.message.isEmpty, !message.uploads.isEmpty {
            bodyLabel.text = "[图片/附件]"
            bodyLabel.textColor = FireTheme.uiInk
            bodyLabel.font = .systemFont(ofSize: 15, weight: .regular)
        } else {
            bodyLabel.text = message.message.isEmpty ? message.previewText : message.message
            bodyLabel.textColor = FireTheme.uiInk
            bodyLabel.font = .systemFont(ofSize: 15, weight: .regular)
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
        loadAvatar(
            template: message.user?.avatarTemplate,
            username: username,
            baseURLString: baseURLString
        )
    }

    private func applyGrouping(_ grouped: Bool) {
        headerStack.isHidden = grouped
        avatarView.isHidden = grouped
        avatarPlaceholder.isHidden = grouped
        contentTopToAvatar?.isActive = !grouped
        contentTopToContent?.isActive = grouped
        // Keep 40×40 avatar slot so the text column never shifts.
        avatarWidth?.constant = 40
        avatarHeight?.constant = 40
        avatarLeading?.constant = 12
    }

    private func loadAvatar(template: String?, username: String, baseURLString: String?) {
        avatarPlaceholder.text = String(username.prefix(1)).uppercased()
        avatarView.image = nil
        let token = UUID()
        avatarLoadToken = token
        guard let url = fireAvatarURL(
            avatarTemplate: template,
            size: 40,
            scale: traitCollection.displayScale,
            baseURLString: baseURLString ?? "https://linux.do"
        ) else {
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                guard let self, self.avatarLoadToken == token else { return }
                self.avatarView.image = image
                self.avatarPlaceholder.text = nil
            }
        }.resume()
    }

    @objc private func threadTapped() {
        onThreadTap?()
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
