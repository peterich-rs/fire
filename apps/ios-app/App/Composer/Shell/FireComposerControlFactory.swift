import UIKit

extension FireComposerViewController {
    func configureTitleField(_ field: UITextField, placeholder: String) {
        field.borderStyle = .roundedRect
        field.placeholder = placeholder
        field.font = .preferredFont(forTextStyle: .title3)
        field.adjustsFontForContentSizeCategory = true
        field.returnKeyType = .next
        field.clearButtonMode = .whileEditing
    }

    func configureSearchField(_ field: UITextField, placeholder: String) {
        field.borderStyle = .roundedRect
        field.placeholder = placeholder
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.clearButtonMode = .whileEditing
    }

    func configureHorizontalStack(_ stack: UIStackView) {
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
    }

    func configureVerticalResultsStack(_ stack: UIStackView) {
        stack.axis = .vertical
        stack.spacing = 0
        stack.backgroundColor = FireComposerPalette.surface
        stack.layer.cornerRadius = FireTheme.mediumCornerRadius
        stack.clipsToBounds = true
    }

    func makePlainButtonConfiguration(title: String, systemImage: String) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = UIImage(systemName: systemImage)
        configuration.imagePadding = 8
        configuration.baseForegroundColor = FireTopicListPalette.accent
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
        return configuration
    }

    func makeToolbarButtonConfiguration(for action: FireMarkdownFormatAction) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.plain()
        if let systemImage = action.systemImage {
            configuration.image = UIImage(systemName: systemImage)
        } else {
            configuration.title = action.title
        }
        configuration.baseForegroundColor = .label
        configuration.contentInsets = .zero
        return configuration
    }

    func makeChipButton(title: String, systemImage: String, emphasized: Bool = true) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = UIImage(systemName: systemImage)
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 6
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = emphasized
            ? FireTopicListPalette.accent.withAlphaComponent(0.12)
            : UIColor.tertiarySystemFill
        configuration.baseForegroundColor = emphasized ? FireTopicListPalette.accent : .secondaryLabel
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        let button = UIButton(type: .system)
        button.configuration = configuration
        button.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
        button.fireBindPressBounce(.compact)
        return button
    }

    func makeResultButton(
        title: String,
        subtitle: String?,
        systemImage: String?,
        monogram: String? = nil
    ) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.subtitle = subtitle
        configuration.imagePadding = 10
        configuration.baseForegroundColor = .label
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
        if let systemImage {
            configuration.image = UIImage(systemName: systemImage)
        } else if let monogram {
            configuration.image = FireComposerMonogramRenderer.image(text: monogram)
        }
        let button = UIButton(type: .system)
        button.configuration = configuration
        button.contentHorizontalAlignment = .leading
        button.fireBindPressBounce(.compact)
        return button
    }

    func makeLabel(
        _ text: String,
        style: UIFont.TextStyle,
        color: UIColor,
        weight: UIFont.Weight? = nil
    ) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = weight.map { UIFont.preferredFont(forTextStyle: style).withComposerWeight($0) }
            ?? .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    func setTextField(_ field: UITextField, text: String) {
        guard field.text != text, !field.isFirstResponder else { return }
        field.text = text
    }

}
