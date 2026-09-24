import UIKit

final class FireSearchHeaderView: UIView, UITextFieldDelegate {
    let stackView = UIStackView()
    let searchRow = UIStackView()
    let backButton = UIButton(type: .system)
    let searchTextField = UISearchTextField()
    let scopeControl = UISegmentedControl(items: FireSearchScope.allCases.map(\.title))
    var onQueryChanged: ((String) -> Void)?
    var onSubmit: (() -> Void)?
    var onClear: (() -> Void)?
    var onScopeChanged: ((FireSearchScope) -> Void)?
    var onBack: (() -> Void)?
    var isProgrammaticUpdate = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        query: String,
        scope: FireSearchScope,
        onQueryChanged: @escaping (String) -> Void,
        onSubmit: @escaping () -> Void,
        onClear: @escaping () -> Void,
        onScopeChanged: @escaping (FireSearchScope) -> Void
    ) {
        self.onQueryChanged = onQueryChanged
        self.onSubmit = onSubmit
        self.onClear = onClear
        self.onScopeChanged = onScopeChanged
        update(query: query, scope: scope)
    }

    func setShowsBackButton(_ shows: Bool, onBack: (() -> Void)?) {
        self.onBack = onBack
        backButton.isHidden = !shows
        backButton.isEnabled = shows
    }

    func update(query: String, scope: FireSearchScope) {
        isProgrammaticUpdate = true
        if searchTextField.text != query {
            searchTextField.text = query
        }
        if let index = FireSearchScope.allCases.firstIndex(of: scope),
           scopeControl.selectedSegmentIndex != index {
            scopeControl.selectedSegmentIndex = index
        }
        isProgrammaticUpdate = false
    }

    func focusSearchField() {
        searchTextField.becomeFirstResponder()
    }

    func configureSubviews() {
        backgroundColor = FireTheme.uiCanvas
        directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 8,
            leading: 16,
            bottom: 10,
            trailing: 16
        )

        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false

        searchRow.axis = .horizontal
        searchRow.alignment = .center
        searchRow.spacing = 8

        var backConfiguration = UIButton.Configuration.plain()
        backConfiguration.image = UIImage(systemName: "chevron.backward")
        backConfiguration.baseForegroundColor = FireTheme.uiAccent
        backConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 4)
        backButton.configuration = backConfiguration
        backButton.accessibilityLabel = "返回"
        backButton.isHidden = true
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backButton.setContentHuggingPriority(.required, for: .horizontal)
        backButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        searchTextField.placeholder = "搜索话题、帖子、用户..."
        searchTextField.returnKeyType = .search
        searchTextField.autocorrectionType = .no
        searchTextField.autocapitalizationType = .none
        searchTextField.clearButtonMode = .whileEditing
        searchTextField.delegate = self
        searchTextField.addTarget(self, action: #selector(queryDidChange), for: .editingChanged)

        scopeControl.selectedSegmentIndex = 0
        scopeControl.addTarget(self, action: #selector(scopeDidChange), for: .valueChanged)

        searchRow.addArrangedSubview(backButton)
        searchRow.addArrangedSubview(searchTextField)
        stackView.addArrangedSubview(searchRow)
        stackView.addArrangedSubview(scopeControl)

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
            searchTextField.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
        ])
    }

    @objc func backTapped() {
        onBack?()
    }

    @objc func queryDidChange() {
        guard !isProgrammaticUpdate else { return }
        let query = searchTextField.text ?? ""
        onQueryChanged?(query)
        if query.isEmpty {
            onClear?()
        }
    }

    @objc func scopeDidChange() {
        guard !isProgrammaticUpdate else { return }
        let index = scopeControl.selectedSegmentIndex
        guard FireSearchScope.allCases.indices.contains(index) else { return }
        onScopeChanged?(FireSearchScope.allCases[index])
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        onSubmit?()
        textField.resignFirstResponder()
        return true
    }
}
