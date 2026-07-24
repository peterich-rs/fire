import Combine
import SwiftUI
import UIKit

/// UIKit public profile screen. Secondary destinations (follow lists, badges)
/// may still push SwiftUI hosts; the page shell is UIKit.
@MainActor
final class FirePublicProfileViewController: UIViewController {
    private enum Section: Int, CaseIterable {
        case error
        case header
        case actions
        case social
        case activity
    }

    private let appViewModel: FireAppViewModel
    private let username: String
    private let topicDetailStore: FireTopicDetailStore
    private let topicRoutePresenter: FireTopicRoutePresenter
    private let profileViewModel: FireProfileViewModel
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var cancellables: Set<AnyCancellable> = []
    private var isUpdatingFollow = false

    init(
        viewModel: FireAppViewModel,
        username: String,
        topicDetailStore: FireTopicDetailStore,
        topicRoutePresenter: FireTopicRoutePresenter
    ) {
        self.appViewModel = viewModel
        self.username = username
        self.topicDetailStore = topicDetailStore
        self.topicRoutePresenter = topicRoutePresenter
        self.profileViewModel = FireProfileViewModel(appViewModel: viewModel, fixedUsername: username)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = username
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = FireTheme.uiCanvas
        navigationController?.navigationBar.tintColor = FireTheme.uiAccent

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = FireTheme.uiCanvas
        tableView.separatorColor = FireTheme.uiDivider
        tableView.sectionHeaderTopPadding = 18
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.register(FireProfileHeaderTableCell.self, forCellReuseIdentifier: FireProfileHeaderTableCell.reuseID)
        tableView.register(FireProfileActivityTableCell.self, forCellReuseIdentifier: FireProfileActivityTableCell.reuseID)
        tableView.refreshControl = UIRefreshControl()
        tableView.refreshControl?.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        profileViewModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.title = self?.displayUsername
                self?.tableView.reloadData()
                self?.tableView.refreshControl?.endRefreshing()
            }
            .store(in: &cancellables)

        profileViewModel.syncWithCurrentSession()
    }

    @objc
    private func handleRefresh() {
        Task { [weak self] in
            await self?.profileViewModel.refreshAll()
            self?.tableView.refreshControl?.endRefreshing()
        }
    }

    private var displayUsername: String {
        profileViewModel.currentUsername ?? username
    }

    private var displayName: String {
        let trimmed = profileViewModel.profile?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? displayUsername : trimmed
    }

    private var isOwnProfile: Bool {
        let current = appViewModel.session.bootstrap.currentUsername?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return current?.caseInsensitiveCompare(displayUsername) == .orderedSame
    }

    private var canFollow: Bool {
        !isOwnProfile && (profileViewModel.profile?.canFollow ?? false)
    }

    private var canMessage: Bool {
        !isOwnProfile && (profileViewModel.profile?.canSendPrivateMessageToUser ?? false)
    }

    private var recentActions: [UserActionState] {
        Array(profileViewModel.actions.prefix(4))
    }

    private func toggleFollow() {
        guard canFollow, !isUpdatingFollow else { return }
        isUpdatingFollow = true
        FireMotionHaptics.selection()
        Task { [weak self] in
            guard let self else { return }
            defer { self.isUpdatingFollow = false }
            do {
                if profileViewModel.profile?.isFollowed == true {
                    try await appViewModel.unfollowUser(username: displayUsername)
                } else {
                    try await appViewModel.followUser(username: displayUsername)
                    _ = FireMotionCelebrationGate.consumeFirstFollow()
                }
                await profileViewModel.refreshAll()
                FireUIKitToast.show(
                    (profileViewModel.profile?.isFollowed ?? false) ? "已关注" : "已取消关注",
                    style: .success,
                    in: view
                )
            } catch {
                FireUIKitToast.show(error.localizedDescription, style: .error, in: view)
            }
            tableView.reloadData()
        }
    }

    private func openMessageComposer() {
        FireMotionHaptics.selection()
        let composer = FireComposerViewController(
            viewModel: appViewModel,
            route: FireComposerRoute(
                kind: .privateMessage(recipients: [displayUsername], title: nil)
            )
        )
        let nav = UINavigationController(rootViewController: composer)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    private func pushHosting<Content: View>(_ root: Content) {
        let host = FireHosting.controller(
            rootView: root
                .environmentObject(topicDetailStore)
                .fireTopicRoutePresenter(topicRoutePresenter)
        )
        navigationController?.pushViewController(host, animated: true)
    }
}

extension FirePublicProfileViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        switch section {
        case .error:
            return (profileViewModel.errorMessage ?? appViewModel.errorMessage) == nil ? 0 : 1
        case .header:
            return 1
        case .actions:
            var count = 0
            if canFollow { count += 1 }
            if canMessage { count += 1 }
            return count
        case .social:
            return 2
        case .activity:
            if recentActions.isEmpty { return 1 }
            return recentActions.count + 1
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        Section(rawValue: section) == .activity ? "最近动态" : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else { return UITableViewCell() }
        switch section {
        case .error:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = profileViewModel.errorMessage ?? appViewModel.errorMessage
            content.textProperties.color = FireTheme.uiError
            cell.contentConfiguration = content
            cell.selectionStyle = .none
            return cell
        case .header:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: FireProfileHeaderTableCell.reuseID,
                for: indexPath
            ) as! FireProfileHeaderTableCell
            cell.configure(
                displayName: displayName,
                username: displayUsername,
                avatarTemplate: profileViewModel.profile?.avatarTemplate,
                bio: profileViewModel.profile?.bioCooked.flatMap { FireProfileFormat.plainText(fromHTML: $0) },
                trustLevel: profileViewModel.profile?.trustLevel,
                followers: profileViewModel.profile?.totalFollowers ?? 0,
                likes: profileViewModel.summary?.stats.likesReceived ?? 0,
                following: profileViewModel.profile?.totalFollowing ?? 0
            )
            return cell
        case .actions:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            var content = cell.defaultContentConfiguration()
            let following = profileViewModel.profile?.isFollowed ?? false
            if canFollow && indexPath.row == 0 {
                content.text = following ? "取消关注" : "关注"
                content.image = UIImage(systemName: following ? "person.badge.minus" : "person.badge.plus")
                content.imageProperties.tintColor = FireTheme.uiAccent
            } else {
                content.text = "发送私信"
                content.image = UIImage(systemName: "envelope")
                content.imageProperties.tintColor = FireTheme.uiAccent
            }
            cell.contentConfiguration = content
            return cell
        case .social:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            var content = cell.defaultContentConfiguration()
            if indexPath.row == 0 {
                content.text = "关注"
                content.secondaryText = FireProfileFormat.number(profileViewModel.profile?.totalFollowing ?? 0)
                content.image = UIImage(systemName: "person.2")
            } else {
                content.text = "粉丝"
                content.secondaryText = FireProfileFormat.number(profileViewModel.profile?.totalFollowers ?? 0)
                content.image = UIImage(systemName: "person.2.fill")
            }
            content.imageProperties.tintColor = FireTheme.uiAccent
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            return cell
        case .activity:
            if recentActions.isEmpty {
                let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
                var content = cell.defaultContentConfiguration()
                content.text = profileViewModel.hasLoadedActionsOnce ? "暂无动态" : "正在加载动态…"
                content.textProperties.color = FireTheme.uiTertiaryInk
                cell.contentConfiguration = content
                cell.selectionStyle = .none
                return cell
            }
            if indexPath.row == recentActions.count {
                let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
                var content = cell.defaultContentConfiguration()
                content.text = "查看全部动态"
                content.image = UIImage(systemName: "list.bullet")
                content.imageProperties.tintColor = FireTheme.uiAccent
                cell.contentConfiguration = content
                cell.accessoryType = .disclosureIndicator
                return cell
            }
            let cell = tableView.dequeueReusableCell(
                withIdentifier: FireProfileActivityTableCell.reuseID,
                for: indexPath
            ) as! FireProfileActivityTableCell
            cell.configure(action: recentActions[indexPath.row])
            cell.accessoryType = .disclosureIndicator
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let section = Section(rawValue: indexPath.section) else { return }
        switch section {
        case .error, .header:
            break
        case .actions:
            if canFollow && indexPath.row == 0 {
                toggleFollow()
            } else {
                openMessageComposer()
            }
        case .social:
            let kind: FireFollowListViewModel.Kind = indexPath.row == 0 ? .following : .followers
            pushHosting(
                FireFollowListView(
                    viewModel: appViewModel,
                    username: displayUsername,
                    kind: kind
                )
            )
        case .activity:
            guard !recentActions.isEmpty else { return }
            if indexPath.row == recentActions.count {
                pushHosting(
                    FireProfileActivityTimelineView(
                        viewModel: appViewModel,
                        profileViewModel: profileViewModel
                    )
                )
                return
            }
            if let route = FireAppRoute.topic(action: recentActions[indexPath.row]) {
                _ = topicRoutePresenter.present(route)
            }
        }
    }
}
