import UIKit

// MARK: - Menu row (colored icon well · title · trailing value · chevron)

/// Compact profile shortcut row with reference-style colored icon wells.
/// Counts sit on the same line, left of the chevron.
final class FireProfileMenuRowCell: UITableViewCell {
    static let reuseID = "FireProfileMenuRowCell"
    static let preferredHeight: CGFloat = 48

    private let iconWell = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let chevronView = UIImageView()
    private let rowStack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default
        accessoryType = .none
        // System disclosure is replaced by our chevron so value can sit next to it.
        preservesSuperviewLayoutMargins = false
        contentView.preservesSuperviewLayoutMargins = false
        contentView.insetsLayoutMarginsFromSafeArea = false

        iconWell.fireApplyIconWellStyle()
        iconWell.setContentHuggingPriority(.required, for: .horizontal)
        iconWell.setContentCompressionResistancePriority(.required, for: .horizontal)

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .white
        iconWell.addSubview(iconView)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 16, weight: .regular)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = FireTheme.uiInk
        titleLabel.numberOfLines = 1
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        valueLabel.font = .systemFont(ofSize: 15, weight: .regular)
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.textColor = FireTheme.uiTertiaryInk
        valueLabel.textAlignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let chevronConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        chevronView.image = UIImage(systemName: "chevron.right", withConfiguration: chevronConfig)
        chevronView.tintColor = FireTheme.uiTertiaryInk
        chevronView.setContentHuggingPriority(.required, for: .horizontal)

        rowStack.axis = .horizontal
        rowStack.alignment = .center
        rowStack.spacing = 12
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        rowStack.addArrangedSubview(iconWell)
        rowStack.addArrangedSubview(titleLabel)
        rowStack.addArrangedSubview(valueLabel)
        rowStack.addArrangedSubview(chevronView)
        contentView.addSubview(rowStack)

        NSLayoutConstraint.activate([
            iconWell.widthAnchor.constraint(equalToConstant: FireTheme.iconWellSize),
            iconWell.heightAnchor.constraint(equalToConstant: FireTheme.iconWellSize),
            iconView.centerXAnchor.constraint(equalTo: iconWell.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconWell.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 15),
            iconView.heightAnchor.constraint(equalToConstant: 15),
            rowStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            rowStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            rowStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 0),
            rowStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: 0),
            rowStack.heightAnchor.constraint(equalToConstant: Self.preferredHeight),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        systemImage: String,
        title: String,
        value: String? = nil,
        iconWellColor: UIColor
    ) {
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        iconView.image = UIImage(systemName: systemImage, withConfiguration: config)
        iconView.tintColor = .white
        iconWell.backgroundColor = iconWellColor

        titleLabel.text = title

        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        valueLabel.text = trimmed
        valueLabel.isHidden = trimmed.isEmpty

        accessibilityLabel = [title, trimmed]
            .filter { !$0.isEmpty }
            .joined(separator: "，")
        accessibilityTraits = .button
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        valueLabel.text = nil
        valueLabel.isHidden = true
        iconView.image = nil
        titleLabel.text = nil
        iconWell.backgroundColor = FireTheme.uiIconWell
    }
}
