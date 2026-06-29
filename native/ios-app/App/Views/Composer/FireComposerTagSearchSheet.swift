import UIKit

final class FireComposerTagSearchSheet: UIViewController {
    var onSearch: ((String, @escaping ([TagSearchItemState]) -> Void) -> Void)?
    var onSelected: ((String) -> Void)?

    private let initialResults: [TagSearchItemState]

    private var results: [TagSearchItemState] = []
    private var inFlight: (([TagSearchItemState]) -> Void)?

    private let searchBar = UISearchBar()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    init(initialResults: [TagSearchItemState] = []) {
        self.initialResults = initialResults
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "搜索标签"
        view.backgroundColor = .systemGroupedBackground

        results = initialResults

        searchBar.delegate = self
        searchBar.placeholder = "输入标签名称…"
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchBar)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "tagCell")
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
}

extension FireComposerTagSearchSheet: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            inFlight = nil
            results = initialResults
            tableView.reloadData()
            return
        }

        inFlight = { [weak self] items in
            guard let self else { return }
            self.results = items
            self.tableView.reloadData()
        }
        onSearch?(trimmed) { [weak self] items in
            guard let self else { return }
            guard self.inFlight != nil else { return }
            self.inFlight?(items)
            self.inFlight = nil
        }
    }
}

extension FireComposerTagSearchSheet: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        results.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "tagCell", for: indexPath)
        let item = results[indexPath.row]
        var content = cell.defaultContentConfiguration()
        if item.count > 0 {
            content.text = "#\(item.name)"
            content.secondaryText = "\(item.count)"
        } else {
            content.text = "#\(item.name)"
        }
        content.image = UIImage(systemName: "number")
        content.imageProperties.tintColor = FireTopicListPalette.accent
        cell.contentConfiguration = content
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = results[indexPath.row]
        let name = item.name
        dismiss(animated: true) { [weak self] in
            self?.onSelected?(name)
        }
    }
}
