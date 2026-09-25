import UIKit

final class FireTopicDetailStatsCell: UICollectionViewCell {
    static let reuseID = "FireTopicDetailStatsCell"

    private let dividerView = UIView()
    private let stackView = UIStackView()
    private let replyStat = FireTopicDetailStatView()
    private let viewStat = FireTopicDetailStatView()
    private let interactionStat = FireTopicDetailStatView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        contentView.backgroundColor = FireTheme.uiCanvas
        dividerView.backgroundColor = .separator
        dividerView.translatesAutoresizingMaskIntoConstraints = false

        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fillEqually
        stackView.spacing = 20
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(replyStat)
        stackView.addArrangedSubview(viewStat)
        stackView.addArrangedSubview(interactionStat)

        contentView.addSubview(dividerView)
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            dividerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            dividerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            dividerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            dividerView.heightAnchor.constraint(equalToConstant: 0.5),

            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: dividerView.bottomAnchor, constant: 12),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
        ])
    }

    func configure(replyCount: UInt32, viewCount: UInt32, interactionCount: UInt32?) {
        replyStat.configure(value: "\(replyCount)", label: "回复")
        viewStat.configure(value: "\(viewCount)", label: "浏览")
        interactionStat.configure(value: interactionCount.map(String.init) ?? "...", label: "互动")
        accessibilityLabel = "\(replyCount) 回复，\(viewCount) 浏览"
    }
}

final class FireTopicDetailStatView: UIView {
    private let valueLabel = UILabel()
    private let titleLabel = UILabel()
    private let stackView = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        valueLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: UIFont.monospacedDigitSystemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize,
                weight: .semibold
            )
        )
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.textColor = .label
        valueLabel.textAlignment = .center

        titleLabel.font = .preferredFont(forTextStyle: .caption2)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center

        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 2
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(valueLabel)
        stackView.addArrangedSubview(titleLabel)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func configure(value: String, label: String) {
        valueLabel.text = value
        titleLabel.text = label
    }
}
