import UIKit

extension FireOnboardingViewController {
    func configureBrand() {
        let imageView = UIImageView(image: UIImage(systemName: "flame.fill"))
        imageView.tintColor = .systemOrange
        imageView.contentMode = .scaleAspectFit

        let titleLabel = UILabel()
        titleLabel.text = "Fire"
        titleLabel.font = UIFont.preferredFont(forTextStyle: .title1).withOnboardingWeight(.bold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center

        let subtitleLabel = UILabel()
        subtitleLabel.text = "LinuxDo 原生客户端"
        subtitleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.alignment = .center
        textStack.spacing = 4

        brandStack.axis = .vertical
        brandStack.alignment = .center
        brandStack.spacing = 10
        brandStack.translatesAutoresizingMaskIntoConstraints = false
        brandStack.addArrangedSubview(imageView)
        brandStack.addArrangedSubview(textStack)

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 44),
            imageView.heightAnchor.constraint(equalToConstant: 44),
        ])
    }
}

private extension UIFont {
    func withOnboardingWeight(_ weight: Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
