import UIKit

/// Compact sheet for choosing a subcategory under the currently selected parent.
/// Parent browsing lives in the leading drawer (`FireHomeCategoryDrawerController`).
@MainActor
final class FireHomeSubcategoryPanelController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let homeFeedStore: FireHomeFeedStore
    private let parentCategory: FireTopicCategoryPresentation
    private let childCategories: [FireTopicCategoryPresentation]
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private var selectedCategoryID: UInt64?

    init(
        homeFeedStore: FireHomeFeedStore,
        parent: FireTopicCategoryPresentation,
        children: [FireTopicCategoryPresentation]
    ) {
        self.homeFeedStore = homeFeedStore
        self.parentCategory = parent
        self.childCategories = children
        self.selectedCategoryID = homeFeedStore.selectedHomeCategoryId
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = FireTheme.uiCanvas
        title = parentCategory.displayName
        navigationController?.navigationBar.tintColor = FireTheme.uiAccent
        navigationItem.rightBarButtonItem = makePlainDoneBarButton(action: #selector(doneTapped))

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = FireTheme.uiCanvas
        tableView.rowHeight = 56
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 52, bottom: 0, right: 16)
        tableView.register(FireHomeCategoryRowCell.self, forCellReuseIdentifier: FireHomeCategoryRowCell.reuseID)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        childCategories.count + 1
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "选择子类"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: FireHomeCategoryRowCell.reuseID,
            for: indexPath
        ) as! FireHomeCategoryRowCell
        let accent = UIColor(fireHomeScopeHex: parentCategory.colorHex) ?? FireTheme.uiAccent
        if indexPath.row == 0 {
            cell.configure(
                title: "全部 \(parentCategory.displayName)",
                subtitle: "包含所有子类",
                accent: accent,
                isSelected: selectedCategoryID == parentCategory.id
            )
        } else {
            let child = childCategories[indexPath.row - 1]
            cell.configure(
                title: child.displayName,
                subtitle: nil,
                accent: UIColor(fireHomeScopeHex: child.colorHex) ?? accent,
                isSelected: selectedCategoryID == child.id
            )
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.row == 0 {
            homeFeedStore.selectHomeCategory(parentCategory.id)
        } else {
            homeFeedStore.selectHomeCategory(childCategories[indexPath.row - 1].id)
        }
        dismiss(animated: true)
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }
}

// Back-compat alias used by older call sites during the IA swap.
typealias FireHomeScopePanelController = FireHomeSubcategoryPanelController
