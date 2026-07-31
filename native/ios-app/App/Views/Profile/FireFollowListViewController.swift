import Combine
import SwiftUI
import UIKit

// MARK: - View model (shared by UIKit host + residual SwiftUI)

@MainActor
final class FireFollowListViewModel: ObservableObject {
    enum Kind {
        case following
        case followers

        var title: String {
            switch self {
            case .following:
                return "关注"
            case .followers:
                return "粉丝"
            }
        }

        var emptySystemImage: String {
            switch self {
            case .following:
                return "person.2"
            case .followers:
                return "person.2.fill"
            }
        }
    }

    @Published private(set) var users: [FollowUserState] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoadedOnce = false
    @Published var errorMessage: String?

    private let appViewModel: FireAppViewModel
    private let username: String
    private let kind: Kind

    init(appViewModel: FireAppViewModel, username: String, kind: Kind) {
        self.appViewModel = appViewModel
        self.username = username
        self.kind = kind
    }

    func load(force: Bool = false) async {
        guard force || (!isLoading && users.isEmpty) else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            switch kind {
            case .following:
                users = try await appViewModel.fetchFollowing(username: username)
            case .followers:
                users = try await appViewModel.fetchFollowers(username: username)
            }
            hasLoadedOnce = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - UIKit authoritative surface

/// Follow / followers list. Opens public profiles via UIKit push with a
/// stack-aware topic presenter so nested "最近动态" topic taps never depend on
/// SwiftUI `NavigationLink` environment inheritance.
@MainActor
final class FireFollowListViewController: UIViewController {
    private enum Section: Int, CaseIterable {
        case banner
        case content
    }

    private enum ContentState {
        case loading
        case blockingError(String)
        case empty
        case users
    }

    private let appViewModel: FireAppViewModel
    private let topicDetailStore: FireTopicDetailStore
    private let username: String
    private let kind: FireFollowListViewModel.Kind
    private let preferredTopicRoutePresenter: FireTopicRoutePresenter
    private let listViewModel: FireFollowListViewModel
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var cancellables: Set<AnyCancellable> = []

    init(
        viewModel: FireAppViewModel,
        topicDetailStore: FireTopicDetailStore,
        username: String,
        kind: FireFollowListViewModel.Kind,
        topicRoutePresenter: FireTopicRoutePresenter
    ) {
        self.appViewModel = viewModel
        self.topicDetailStore = topicDetailStore
        self.username = username
        self.kind = kind
        self.preferredTopicRoutePresenter = topicRoutePresenter
        self.listViewModel = FireFollowListViewModel(
            appViewModel: viewModel,
            username: username,
            kind: kind
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = kind.title
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = FireTheme.uiCanvas
        navigationController?.navigationBar.tintColor = FireTheme.uiAccent

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = FireTheme.uiCanvas
        tableView.separatorColor = FireTheme.uiDivider
        tableView.sectionHeaderTopPadding = 12
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.register(FireFollowUserTableCell.self, forCellReuseIdentifier: FireFollowUserTableCell.reuseID)
        tableView.refreshControl = UIRefreshControl()
        tableView.refreshControl?.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        listViewModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.tableView.reloadData()
                self?.tableView.refreshControl?.endRefreshing()
            }
            .store(in: &cancellables)

        Task { [weak self] in
            await self?.listViewModel.load()
        }
    }

    @objc
    private func handleRefresh() {
        Task { [weak self] in
            await self?.listViewModel.load(force: true)
            self?.tableView.refreshControl?.endRefreshing()
        }
    }

    private var contentState: ContentState {
        if !listViewModel.hasLoadedOnce {
            if let errorMessage = listViewModel.errorMessage {
                return .blockingError(errorMessage)
            }
            return .loading
        }
        if listViewModel.users.isEmpty {
            return .empty
        }
        return .users
    }

    private func openProfile(username: String) {
        FireMotionHaptics.selection()
        appViewModel.topicRouteLogger()?.info(
            "follow list open profile username_length=\(username.count) kind=\(kind.title) stack_count=\(navigationController?.viewControllers.count ?? 0)"
        )

        // Nested public profile owns a stack-aware preferred presenter evaluated
        // against the live navigation controller when "最近动态" is tapped.
        // `FirePublicProfileViewController.presentRoute` still runs the full cascade
        // (preferred → live nav → root secondary) so `.local` cannot silent-fail.
        let nestedPresenter = FireAppRouteControllerFactory.makeStackAwareTopicRoutePresenter(
            viewModel: appViewModel,
            topicDetailStore: topicDetailStore,
            navigationControllerProvider: { [weak self] in
                self?.navigationController
                    ?? FireRootCoordinator.activeSecondaryNavigationController
            }
        )
        // Prefer stack push; fall back to the list's injected presenter (often app-root).
        let profilePresenter = FireTopicRoutePresenter { [preferredTopicRoutePresenter, nestedPresenter] route in
            if nestedPresenter.present(route) {
                return true
            }
            return preferredTopicRoutePresenter.present(route)
        }

        let controller = FireAppRouteControllerFactory.makePublicProfileViewController(
            viewModel: appViewModel,
            username: username,
            topicDetailStore: topicDetailStore,
            preferredPresenter: profilePresenter
        )

        if let navigationController {
            navigationController.pushViewController(controller, animated: true)
        } else {
            appViewModel.topicRouteLogger()?.warning(
                "follow list open profile without navigationController; presenting secondary username_length=\(username.count)"
            )
            FireRootCoordinator.presentSecondary(controller)
        }
    }
}

extension FireFollowListViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        switch section {
        case .banner:
            if listViewModel.hasLoadedOnce, listViewModel.errorMessage != nil {
                return 1
            }
            return 0
        case .content:
            switch contentState {
            case .loading, .blockingError, .empty:
                return 1
            case .users:
                return listViewModel.users.count
            }
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else { return UITableViewCell() }
        switch section {
        case .banner:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = listViewModel.errorMessage
            content.textProperties.color = FireTheme.uiError
            content.textProperties.numberOfLines = 0
            cell.contentConfiguration = content
            cell.selectionStyle = .none
            return cell
        case .content:
            switch contentState {
            case .loading:
                let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
                var content = cell.defaultContentConfiguration()
                content.text = "加载中…"
                content.textProperties.color = FireTheme.uiTertiaryInk
                cell.contentConfiguration = content
                cell.selectionStyle = .none
                return cell
            case .blockingError(let message):
                let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
                var content = cell.defaultContentConfiguration()
                content.text = "\(kind.title)列表加载失败"
                content.secondaryText = message
                content.textProperties.color = FireTheme.uiInk
                content.secondaryTextProperties.color = FireTheme.uiError
                content.secondaryTextProperties.numberOfLines = 0
                cell.contentConfiguration = content
                cell.accessoryType = .none
                return cell
            case .empty:
                let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
                var content = cell.defaultContentConfiguration()
                content.text = "@\(username) 还没有\(kind.title)"
                content.image = UIImage(systemName: kind.emptySystemImage)
                content.imageProperties.tintColor = FireTheme.uiSubtleInk
                content.textProperties.color = FireTheme.uiSubtleInk
                cell.contentConfiguration = content
                cell.selectionStyle = .none
                return cell
            case .users:
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: FireFollowUserTableCell.reuseID,
                    for: indexPath
                ) as! FireFollowUserTableCell
                let user = listViewModel.users[indexPath.row]
                cell.configure(user: user)
                cell.accessoryType = .disclosureIndicator
                return cell
            }
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let section = Section(rawValue: indexPath.section) else { return }
        switch section {
        case .banner:
            break
        case .content:
            switch contentState {
            case .blockingError:
                Task { await listViewModel.load(force: true) }
            case .users:
                let user = listViewModel.users[indexPath.row]
                openProfile(username: user.username)
            case .loading, .empty:
                break
            }
        }
    }
}

// MARK: - User row

final class FireFollowUserTableCell: UITableViewCell {
    static let reuseID = "FireFollowUserTableCell"

    private let avatarView = FireTopicListAvatarView()
    private let nameLabel = UILabel()
    private let handleLabel = UILabel()
    private let textStack = UIStackView()
    private let rowStack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default
        backgroundColor = FireTheme.uiSurface

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.layer.cornerRadius = 21
        avatarView.clipsToBounds = true

        nameLabel.font = .systemFont(ofSize: 15, weight: .medium)
        nameLabel.textColor = FireTheme.uiInk
        nameLabel.numberOfLines = 1

        handleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        handleLabel.textColor = FireTheme.uiSubtleInk
        handleLabel.numberOfLines = 1

        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.alignment = .leading
        textStack.addArrangedSubview(nameLabel)
        textStack.addArrangedSubview(handleLabel)

        rowStack.axis = .horizontal
        rowStack.spacing = 12
        rowStack.alignment = .center
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        rowStack.addArrangedSubview(avatarView)
        rowStack.addArrangedSubview(textStack)

        contentView.addSubview(rowStack)
        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 42),
            avatarView.heightAnchor.constraint(equalToConstant: 42),
            rowStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            rowStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            rowStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
        nameLabel.text = nil
        handleLabel.text = nil
    }

    func configure(user: FollowUserState) {
        let displayName = (user.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        nameLabel.text = displayName.isEmpty ? user.username : displayName
        handleLabel.text = "@\(user.username)"
        avatarView.configure(
            username: user.username,
            avatarTemplate: user.avatarTemplate,
            baseURLString: "https://linux.do"
        )
    }
}

// MARK: - Residual SwiftUI host (legacy SwiftUI profile surfaces)

struct FireFollowListControllerHost: UIViewControllerRepresentable {
    @Environment(\.fireTopicRoutePresenter) private var topicRoutePresenter

    let viewModel: FireAppViewModel
    let username: String
    let kind: FireFollowListViewModel.Kind
    let topicDetailStore: FireTopicDetailStore

    init(
        viewModel: FireAppViewModel,
        username: String,
        kind: FireFollowListViewModel.Kind,
        topicDetailStore: FireTopicDetailStore
    ) {
        self.viewModel = viewModel
        self.username = username
        self.kind = kind
        self.topicDetailStore = topicDetailStore
    }

    /// Environment-only entry used by residual SwiftUI profile shortcuts.
    init(
        viewModel: FireAppViewModel,
        username: String,
        kind: FireFollowListViewModel.Kind
    ) {
        self.viewModel = viewModel
        self.username = username
        self.kind = kind
        self.topicDetailStore = FireTopicDetailStore(appViewModel: viewModel)
    }

    func makeUIViewController(context: Context) -> FireFollowListViewController {
        let preferred: FireTopicRoutePresenter
        if topicRoutePresenter.isLocalNoOp {
            preferred = FireAppRouteControllerFactory.makeStackAwareTopicRoutePresenter(
                viewModel: viewModel,
                topicDetailStore: topicDetailStore,
                navigationControllerProvider: {
                    FireRootCoordinator.activeSecondaryNavigationController
                }
            )
        } else {
            preferred = topicRoutePresenter
        }
        return FireFollowListViewController(
            viewModel: viewModel,
            topicDetailStore: topicDetailStore,
            username: username,
            kind: kind,
            topicRoutePresenter: preferred
        )
    }

    func updateUIViewController(_ uiViewController: FireFollowListViewController, context: Context) {}
}

/// Thin SwiftUI entry that always hosts the UIKit follow list.
/// Product navigation no longer uses `NavigationLink` for profile drill-down.
struct FireFollowListView: View {
    @ObservedObject var viewModel: FireAppViewModel
    let username: String
    let kind: FireFollowListViewModel.Kind

    var body: some View {
        FireFollowListControllerHost(
            viewModel: viewModel,
            username: username,
            kind: kind
        )
        .ignoresSafeArea()
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
