import UIKit

final class FireHomeStyleSkeletonCell: UICollectionViewCell {
    private let avatarView = UIView()
    private let titleBar = UIView()
    private let subtitleBar = UIView()

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
        FireUIKitSkeleton.hide(contentView)
    }

    func configure() {
        isAccessibilityElement = false
        FireUIKitSkeleton.show(contentView)
    }

    private func configureSubviews() {
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
        avatarView.layer.cornerRadius = 19
        avatarView.layer.cornerCurve = .continuous
        titleBar.layer.cornerRadius = 4
        subtitleBar.layer.cornerRadius = 4
        let body = UIStackView(arrangedSubviews: [titleBar, subtitleBar])
        body.axis = .vertical
        body.spacing = 6
        let row = UIStackView(arrangedSubviews: [avatarView, body])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 38),
            avatarView.heightAnchor.constraint(equalToConstant: 38),
            titleBar.heightAnchor.constraint(equalToConstant: 14),
            titleBar.widthAnchor.constraint(equalTo: body.widthAnchor),
            subtitleBar.widthAnchor.constraint(equalToConstant: 100),
            subtitleBar.heightAnchor.constraint(equalToConstant: 10),
            row.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            row.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
        FireUIKitSkeleton.prepareHierarchy(in: contentView)
    }
}
