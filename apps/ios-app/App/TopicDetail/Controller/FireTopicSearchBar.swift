import UIKit

@MainActor
final class FireTopicSearchBar: UIView, UITextFieldDelegate {
    var onQueryChanged: ((String) -> Void)?
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onClose: (() -> Void)?

    private let textField = UITextField()
    private let resultLabel = UILabel()
    private let previousButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let stackView = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func focusInput() {
        textField.becomeFirstResponder()
    }

    func reset() {
        textField.text = ""
        updateResult(index: -1, total: 0)
    }

    func updateResult(index: Int, total: Int) {
        resultLabel.text = total > 0 && index >= 0 ? "\(index + 1)/\(total)" : "0/0"
    }

    private func setup() {
        backgroundColor = FireTheme.uiCanvas
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.08
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 2)

        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        textField.borderStyle = .roundedRect
        textField.placeholder = "搜索已加载帖子"
        textField.returnKeyType = .search
        textField.clearButtonMode = .whileEditing
        textField.delegate = self
        textField.addTarget(self, action: #selector(textDidChange), for: .editingChanged)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        resultLabel.font = .preferredFont(forTextStyle: .caption1)
        resultLabel.adjustsFontForContentSizeCategory = true
        resultLabel.textColor = .secondaryLabel
        resultLabel.textAlignment = .center
        resultLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true
        updateResult(index: -1, total: 0)

        configureButton(previousButton, systemName: "chevron.up", label: "上一个结果", action: #selector(previousTapped))
        configureButton(nextButton, systemName: "chevron.down", label: "下一个结果", action: #selector(nextTapped))
        configureButton(closeButton, systemName: "xmark", label: "关闭搜索", action: #selector(closeTapped))

        stackView.addArrangedSubview(textField)
        stackView.addArrangedSubview(resultLabel)
        stackView.addArrangedSubview(previousButton)
        stackView.addArrangedSubview(nextButton)
        stackView.addArrangedSubview(closeButton)

        // Frame-based parent can briefly report 0 size before first layout.
        // Keep padding required only when space exists so autoresizing masks
        // do not fight unbreakable internal edges.
        let edgeConstraints = [
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ]
        edgeConstraints.forEach { $0.priority = UILayoutPriority(999) }
        NSLayoutConstraint.activate(edgeConstraints + [
            previousButton.widthAnchor.constraint(equalToConstant: 34),
            previousButton.heightAnchor.constraint(equalToConstant: 34),
            nextButton.widthAnchor.constraint(equalToConstant: 34),
            nextButton.heightAnchor.constraint(equalToConstant: 34),
            closeButton.widthAnchor.constraint(equalToConstant: 34),
            closeButton.heightAnchor.constraint(equalToConstant: 34),
        ])
    }

    private func configureButton(
        _ button: UIButton,
        systemName: String,
        label: String,
        action: Selector
    ) {
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.tintColor = FireTopicDetailCellColors.accent
        button.accessibilityLabel = label
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    @objc private func textDidChange() {
        onQueryChanged?(textField.text ?? "")
    }

    @objc private func previousTapped() {
        onPrevious?()
    }

    @objc private func nextTapped() {
        onNext?()
    }

    @objc private func closeTapped() {
        onClose?()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        onNext?()
        return true
    }
}
