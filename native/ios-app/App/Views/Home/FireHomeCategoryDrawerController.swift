import UIKit

/// Leading drawer that only commits parent categories / 全部.
/// Subcategories are chosen later from the home status-bar arrow panel.
@MainActor
final class FireHomeCategoryDrawerController: UIViewController {
    private enum Row: Hashable {
        case all
        case parent(UInt64)
    }

    private let homeFeedStore: FireHomeFeedStore
    private let searchField = UISearchTextField()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let onClose: () -> Void

    private var categories: [FireTopicCategoryPresentation] = []
    private var parents: [FireTopicCategoryPresentation] = []
    private var visibleParents: [FireTopicCategoryPresentation] = []
    private var selectedCategoryID: UInt64?
    private var searchText = ""
    private var rows: [Row] = []

    init(homeFeedStore: FireHomeFeedStore, onClose: @escaping () -> Void) {
        self.homeFeedStore = homeFeedStore
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = FireTheme.uiSurface
        title = "分类"

        navigationItem.rightBarButtonItem = makePlainDoneBarButton(action: #selector(closeTapped))
        navigationController?.navigationBar.tintColor = FireTheme.uiAccent

        configureSearch()
        configureTable()
        reloadFromStore()
    }

    private func configureSearch() {
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholder = "搜索分类"
        searchField.backgroundColor = FireTheme.uiSurfaceSecondary
        searchField.tintColor = FireTheme.uiAccent
        searchField.returnKeyType = .search
        searchField.clearButtonMode = .whileEditing
        searchField.borderStyle = .none
        searchField.layer.cornerRadius = 18
        searchField.layer.cornerCurve = .continuous
        searchField.clipsToBounds = true
        searchField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        searchField.leftViewMode = .always
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
    }

    private func configureTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = FireTheme.uiSurface
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 52, bottom: 0, right: 16)
        tableView.rowHeight = 56
        tableView.keyboardDismissMode = .onDrag
        tableView.register(FireHomeCategoryRowCell.self, forCellReuseIdentifier: FireHomeCategoryRowCell.reuseID)

        view.addSubview(searchField)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            searchField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            searchField.heightAnchor.constraint(equalToConstant: 36),

            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func reloadFromStore() {
        categories = homeFeedStore.allCategories
        parents = FireHomeScopePresentation.parents(from: categories)
        selectedCategoryID = homeFeedStore.selectedHomeCategoryId
        applyFilter()
    }

    private func applyFilter() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            visibleParents = parents
        } else {
            visibleParents = parents.filter {
                $0.displayName.lowercased().contains(query) || $0.slug.lowercased().contains(query)
            }
        }
        rows = [.all] + visibleParents.map { .parent($0.id) }
        tableView.reloadData()
    }

    private func category(for id: UInt64) -> FireTopicCategoryPresentation? {
        categories.first(where: { $0.id == id })
    }

    private func selectedParentID() -> UInt64? {
        guard let selectedCategoryID,
              let selected = category(for: selectedCategoryID) else {
            return nil
        }
        return selected.parentCategoryId ?? selected.id
    }

    private func commitParent(_ categoryID: UInt64?) {
        // Drawer only ever commits parent / 全部. Children stay on the home arrow panel.
        homeFeedStore.selectHomeCategory(categoryID)
        onClose()
    }

    @objc private func searchChanged() {
        searchText = searchField.text ?? ""
        applyFilter()
    }

    @objc private func closeTapped() {
        onClose()
    }
}

extension FireHomeCategoryDrawerController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: FireHomeCategoryRowCell.reuseID,
            for: indexPath
        ) as! FireHomeCategoryRowCell

        switch rows[indexPath.row] {
        case .all:
            cell.configure(
                title: "全部",
                subtitle: "不限分类",
                accent: FireTheme.uiAccent,
                isSelected: selectedCategoryID == nil
            )
        case let .parent(id):
            let parent = category(for: id)
            let childCount = FireHomeScopePresentation.children(of: id, in: categories).count
            let isSelected = selectedParentID() == id
            let subtitle: String? = {
                guard childCount > 0 else { return nil }
                if isSelected,
                   let selectedCategoryID,
                   let selected = category(for: selectedCategoryID),
                   selected.parentCategoryId == id {
                    return "当前：\(selected.displayName)"
                }
                if isSelected, selectedCategoryID == id {
                    return "已选大类"
                }
                return "\(childCount) 个子类 · 首页箭头可选"
            }()
            cell.configure(
                title: parent?.displayName ?? "Category #\(id)",
                subtitle: subtitle,
                accent: UIColor(fireHomeScopeHex: parent?.colorHex) ?? FireTheme.uiAccent,
                isSelected: isSelected
            )
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch rows[indexPath.row] {
        case .all:
            commitParent(nil)
        case let .parent(id):
            commitParent(id)
        }
    }
}

// MARK: - Leading drawer host

@MainActor
enum FireHomeCategoryDrawerPresenter {
    /// Slides a leading drawer over `host` without fighting the interactive-pop edge.
    static func present(from host: UIViewController, homeFeedStore: FireHomeFeedStore) {
        let drawerWidth = min(host.view.bounds.width * 0.82, 340)
        let container = FireHomeCategoryDrawerContainerController(
            homeFeedStore: homeFeedStore,
            drawerWidth: drawerWidth
        )
        container.modalPresentationStyle = .overFullScreen
        container.modalTransitionStyle = .crossDissolve
        host.present(container, animated: false)
    }
}

@MainActor
private final class FireHomeCategoryDrawerContainerController: UIViewController {
    private let homeFeedStore: FireHomeFeedStore
    private let drawerWidth: CGFloat
    private let dimmingView = UIControl()
    private let panelContainer = UIView()
    private var panelLeadingConstraint: NSLayoutConstraint?
    private var embeddedNavigation: UINavigationController?

    init(homeFeedStore: FireHomeFeedStore, drawerWidth: CGFloat) {
        self.homeFeedStore = homeFeedStore
        self.drawerWidth = drawerWidth
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        dimmingView.alpha = 0
        dimmingView.addTarget(self, action: #selector(close), for: .touchUpInside)

        panelContainer.translatesAutoresizingMaskIntoConstraints = false
        panelContainer.backgroundColor = FireTheme.uiSurface
        panelContainer.layer.shadowColor = UIColor.black.cgColor
        panelContainer.layer.shadowOpacity = 0.28
        panelContainer.layer.shadowRadius = 18
        panelContainer.layer.shadowOffset = CGSize(width: 4, height: 0)
        panelContainer.clipsToBounds = false

        let drawer = FireHomeCategoryDrawerController(homeFeedStore: homeFeedStore) { [weak self] in
            self?.close()
        }
        let navigation = UINavigationController(rootViewController: drawer)
        navigation.view.translatesAutoresizingMaskIntoConstraints = false
        navigation.navigationBar.prefersLargeTitles = false
        embeddedNavigation = navigation

        view.addSubview(dimmingView)
        view.addSubview(panelContainer)
        addChild(navigation)
        panelContainer.addSubview(navigation.view)
        navigation.didMove(toParent: self)

        let leading = panelContainer.leadingAnchor.constraint(
            equalTo: view.leadingAnchor,
            constant: -drawerWidth
        )
        panelLeadingConstraint = leading

        NSLayoutConstraint.activate([
            dimmingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimmingView.topAnchor.constraint(equalTo: view.topAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            leading,
            panelContainer.topAnchor.constraint(equalTo: view.topAnchor),
            panelContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            panelContainer.widthAnchor.constraint(equalToConstant: drawerWidth),

            navigation.view.leadingAnchor.constraint(equalTo: panelContainer.leadingAnchor),
            navigation.view.trailingAnchor.constraint(equalTo: panelContainer.trailingAnchor),
            navigation.view.topAnchor.constraint(equalTo: panelContainer.topAnchor),
            navigation.view.bottomAnchor.constraint(equalTo: panelContainer.bottomAnchor),
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panelContainer.addGestureRecognizer(pan)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        openAnimated()
    }

    private func openAnimated() {
        view.layoutIfNeeded()
        panelLeadingConstraint?.constant = 0
        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.92,
            initialSpringVelocity: 0.4,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.dimmingView.alpha = 1
            self.view.layoutIfNeeded()
        }
    }

    @objc private func close() {
        panelLeadingConstraint?.constant = -drawerWidth
        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            options: [.curveEaseIn, .allowUserInteraction]
        ) {
            self.dimmingView.alpha = 0
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.dismiss(animated: false)
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view).x
        switch gesture.state {
        case .changed:
            let offset = min(0, max(-drawerWidth, translation))
            panelLeadingConstraint?.constant = offset
            dimmingView.alpha = 1 - (abs(offset) / drawerWidth) * 0.85
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: view).x
            let shouldClose = panelLeadingConstraint?.constant ?? 0 < -drawerWidth * 0.35 || velocity < -500
            if shouldClose {
                close()
            } else {
                openAnimated()
            }
        default:
            break
        }
    }
}

// MARK: - Shared row cell

final class FireHomeCategoryRowCell: UITableViewCell {
    static let reuseID = "FireHomeCategoryRowCell"

    private let swatchView = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let checkView = UIImageView()
    private let textStack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = FireTheme.uiSurface
        contentView.backgroundColor = FireTheme.uiSurface
        selectionStyle = .default

        swatchView.translatesAutoresizingMaskIntoConstraints = false
        swatchView.layer.cornerRadius = 3
        swatchView.layer.cornerCurve = .continuous

        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = FireTheme.uiInk

        subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = FireTheme.uiSubtleInk

        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)

        checkView.translatesAutoresizingMaskIntoConstraints = false
        checkView.tintColor = FireTheme.uiAccent
        checkView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)

        contentView.addSubview(swatchView)
        contentView.addSubview(textStack)
        contentView.addSubview(checkView)

        NSLayoutConstraint.activate([
            swatchView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            swatchView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            swatchView.widthAnchor.constraint(equalToConstant: 6),
            swatchView.heightAnchor.constraint(equalToConstant: 24),

            textStack.leadingAnchor.constraint(equalTo: swatchView.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: checkView.leadingAnchor, constant: -8),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 10),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),

            checkView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            checkView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkView.widthAnchor.constraint(equalToConstant: 18),
            checkView.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        title: String,
        subtitle: String?,
        accent: UIColor,
        isSelected: Bool
    ) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil || subtitle?.isEmpty == true
        swatchView.backgroundColor = accent
        checkView.image = isSelected ? UIImage(systemName: "checkmark.circle.fill") : nil
        checkView.isHidden = !isSelected
        titleLabel.textColor = isSelected ? FireTheme.uiAccent : FireTheme.uiInk
        titleLabel.font = .preferredFont(forTextStyle: .body).withHomeDrawerWeight(isSelected ? .semibold : .regular)
        accessibilityLabel = subtitle.map { "\(title)，\($0)" } ?? title
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }
}

private extension UIFont {
    func withHomeDrawerWeight(_ weight: Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

extension UIViewController {
    /// Prefer plain text over `.done` so newer OS versions do not promote a filled capsule.
    /// Avoid iOS 26-only bar-button APIs (`sharesBackground`) — CI toolchains may lack them.
    func makePlainDoneBarButton(action: Selector) -> UIBarButtonItem {
        let item = UIBarButtonItem(
            title: "完成",
            style: .plain,
            target: self,
            action: action
        )
        item.tintColor = FireTheme.uiAccent
        return item
    }
}
