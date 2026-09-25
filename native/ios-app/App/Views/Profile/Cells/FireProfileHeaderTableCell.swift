import UIKit

// MARK: - Header

final class FireProfileHeaderTableCell: UITableViewCell {
    static let reuseID = "FireProfileHeaderTableCell"

    private let avatarView = FireTopicListAvatarView()
    private let nameLabel = UILabel()
    private let usernameLabel = UILabel()
    private let bioLabel = UILabel()
    private let statsStack = UIStackView()
    private let stack = UIStackView()
    private var statColumns: [(value: UILabel, label: UILabel)] = []

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        var background = UIBackgroundConfiguration.listGroupedCell()
        background.backgroundColor = FireTheme.uiSurface
        background.cornerRadius = FireTheme.cornerRadius
        backgroundConfiguration = background

        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        let textColumn = UIStackView(arrangedSubviews: [nameLabel, usernameLabel, bioLabel])
        textColumn.axis = .vertical
        textColumn.spacing = 2
        textColumn.alignment = .leading

        let top = UIStackView(arrangedSubviews: [avatarView, textColumn])
        top.axis = .horizontal
        top.alignment = .center
        top.spacing = 12

        nameLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        nameLabel.numberOfLines = 2
        nameLabel.textColor = FireTheme.uiInk
        usernameLabel.font = .systemFont(ofSize: 14, weight: .regular)
        usernameLabel.textColor = FireTheme.uiSubtleInk
        bioLabel.font = .systemFont(ofSize: 13, weight: .regular)
        bioLabel.textColor = FireTheme.uiSubtleInk
        bioLabel.numberOfLines = 2

        statsStack.axis = .horizontal
        statsStack.alignment = .center
        statsStack.distribution = .fillEqually
        statsStack.spacing = 0

        for title in ["粉丝", "获赞", "关注"] {
            let valueLabel = UILabel()
            valueLabel.font = .systemFont(ofSize: 17, weight: .semibold)
            valueLabel.textColor = FireTheme.uiInk
            valueLabel.textAlignment = .center
            valueLabel.adjustsFontForContentSizeCategory = true

            let caption = UILabel()
            caption.font = .systemFont(ofSize: 12, weight: .regular)
            caption.textColor = FireTheme.uiTertiaryInk
            caption.textAlignment = .center
            caption.text = title

            let column = UIStackView(arrangedSubviews: [valueLabel, caption])
            column.axis = .vertical
            column.alignment = .center
            column.spacing = 2
            statsStack.addArrangedSubview(column)
            statColumns.append((valueLabel, caption))
        }

        // Soft surface strip behind stats for a less sparse header.
        let statsCard = UIView()
        statsCard.fireApplyCardStyle(cornerRadius: FireTheme.smallCornerRadius, fill: FireTheme.uiSurfaceSecondary)
        statsCard.addSubview(statsStack)
        statsStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statsStack.leadingAnchor.constraint(equalTo: statsCard.leadingAnchor, constant: 8),
            statsStack.trailingAnchor.constraint(equalTo: statsCard.trailingAnchor, constant: -8),
            statsStack.topAnchor.constraint(equalTo: statsCard.topAnchor, constant: 8),
            statsStack.bottomAnchor.constraint(equalTo: statsCard.bottomAnchor, constant: -8),
        ])

        stack.addArrangedSubview(top)
        stack.addArrangedSubview(statsCard)
        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 56),
            avatarView.heightAnchor.constraint(equalToConstant: 56),
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor, constant: -4),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        displayName: String,
        username: String,
        avatarTemplate: String?,
        bio: String?,
        trustLevel: UInt32?,
        followers: UInt32,
        likes: UInt32,
        following: UInt32
    ) {
        avatarView.configure(username: username, avatarTemplate: avatarTemplate, baseURLString: "https://linux.do")
        nameLabel.text = displayName
        usernameLabel.text = "@\(username)" + (trustLevel.map { " · TL\($0)" } ?? "")
        bioLabel.text = bio
        bioLabel.isHidden = (bio?.isEmpty ?? true)

        let values = [
            FireProfileFormat.number(followers),
            FireProfileFormat.number(likes),
            FireProfileFormat.number(following),
        ]
        for (index, column) in statColumns.enumerated() where index < values.count {
            column.value.text = values[index]
        }
    }
}
