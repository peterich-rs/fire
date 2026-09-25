import UIKit

final class FireTopicDetailRepliesHeaderCell: UICollectionViewCell {
    static let reuseID = "FireTopicDetailRepliesHeaderCell"

    private let titleLabel = UILabel()
    private let countLabel = UILabel()
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
        contentView.backgroundColor = FireTheme.uiCanvas

        titleLabel.text = "回复"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label

        countLabel.font = .preferredFont(forTextStyle: .subheadline)
        countLabel.adjustsFontForContentSizeCategory = true
        countLabel.textColor = .secondaryLabel
        countLabel.textAlignment = .right
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(countLabel)
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
        ])
    }

    func configure(loadedReplyCount: Int, totalReplyCount: Int, displayedFloorCount: Int, hasDetail: Bool) {
        if hasDetail {
            if loadedReplyCount < totalReplyCount {
                countLabel.text = "已加载 \(loadedReplyCount) / \(totalReplyCount) 条"
            } else {
                countLabel.text = "\(totalReplyCount) 条 · \(displayedFloorCount) 楼"
            }
        } else {
            countLabel.text = nil
        }
        accessibilityLabel = [titleLabel.text, countLabel.text]
            .compactMap { $0 }
            .joined(separator: "，")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        configure(loadedReplyCount: 0, totalReplyCount: 0, displayedFloorCount: 0, hasDetail: false)
    }
}

