import UIKit

final class FireCategoryPickerSheet: UIViewController {
    var onSelected: ((UInt64) -> Void)?

    private let categories: [FireTopicCategoryPresentation]
    private let displayName: (FireTopicCategoryPresentation) -> String
    private let selectedCategoryID: UInt64?

    private var filteredCategories: [FireTopicCategoryPresentation] = []
    private let searchBar = UISearchBar()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    init(
        categories: [FireTopicCategoryPresentation],
        selectedCategoryID: UInt64?,
        displayName: @escaping (FireTopicCategoryPresentation) -> String
    ) {
        self.categories = categories
        self.selectedCategoryID = selectedCategoryID
        self.displayName = displayName
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "选择分类"
        view.backgroundColor = .systemGroupedBackground

        filteredCategories = categories

        searchBar.delegate = self
        searchBar.placeholder = "搜索分类"
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchBar)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "categoryCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func filter(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty {
            filteredCategories = categories
        } else {
            filteredCategories = categories.filter { category in
                displayName(category).lowercased().contains(trimmed)
            }
        }
        tableView.reloadData()
    }
}

extension FireCategoryPickerSheet: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        filter(searchText)
    }
}

extension FireCategoryPickerSheet: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filteredCategories.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "categoryCell", for: indexPath)
        let category = filteredCategories[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = displayName(category)
        content.image = UIImage(systemName: "folder")
        content.imageProperties.tintColor = FireTopicListPalette.accent
        cell.contentConfiguration = content
        cell.accessoryType = category.id == selectedCategoryID ? .checkmark : .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let category = filteredCategories[indexPath.row]
        let selected = category.id
        dismiss(animated: true) { [weak self] in
            self?.onSelected?(selected)
        }
    }
}
