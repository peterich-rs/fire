import Combine
import SnapKit
import SwiftUI
import UIKit

/// UIKit profile tab hub using the unified black-canvas + elevated-card language.
@MainActor
final class FireProfileViewController: UIViewController {
    private enum Section: Int, CaseIterable {
        case error
        case header
        case social
        case content
        case account
    }

    private enum SocialRow: Int, CaseIterable {
        case following
        case followers

        var title: String {
            switch self {
            case .following: return "关注列表"
            case .followers: return "粉丝列表"
            }
        }

        var systemImage: String {
            switch self {
            case .following: return "person.2.fill"
            case .followers: return "person.3.fill"
            }
        }

        var iconWellColor: UIColor {
            switch self {
            case .following: return UIColor.systemBlue
            case .followers: return UIColor.systemIndigo
            }
        }
    }

    private enum ContentRow: Int, CaseIterable {
        case activity
        case bookmarks
        case history
        case drafts
        case messages
        case badges

        var title: String {
            switch self {
            case .activity: return "我的动态"
            case .bookmarks: return "我的书签"
            case .history: return "浏览历史"
            case .drafts: return "草稿箱"
            case .messages: return "私信"
            case .badges: return "我的勋章"
            }
        }

        var systemImage: String {
            switch self {
            case .activity: return "list.bullet.rectangle.fill"
            case .bookmarks: return "bookmark.fill"
            case .history: return "clock.fill"
            case .drafts: return "doc.text.fill"
            case .messages: return "envelope.fill"
            case .badges: return "rosette"
            }
        }

        var iconWellColor: UIColor {
            switch self {
            case .activity: return UIColor.systemGray
            case .bookmarks: return UIColor.systemOrange
            case .history: return UIColor.systemPurple
            case .drafts: return UIColor.systemTeal
            case .messages: return UIColor.systemBlue
            case .badges:
                return UIColor(red: 0.86, green: 0.62, blue: 0.16, alpha: 1)
            }
        }
    }

    private enum AccountRow: Int, CaseIterable {
        /// Early-beta primary entry: keep first for discoverability.
        case feedback
        case invites
        case ldc
        case cdk
        case settings

        var title: String {
            switch self {
            case .feedback: return "反馈与建议"
            case .invites: return "邀请链接"
            case .ldc: return "LDC 信用"
            case .cdk: return "CDK 连接"
            case .settings: return "设置"
            }
        }

        var systemImage: String {
            switch self {
            case .feedback: return "bubble.left.and.exclamationmark.bubble.right.fill"
            case .invites: return "ticket.fill"
            case .ldc: return "creditcard.fill"
            case .cdk: return "key.fill"
            case .settings: return "gearshape.fill"
            }
        }

        var iconWellColor: UIColor {
            switch self {
            case .feedback: return UIColor.systemOrange
            case .invites: return UIColor.systemGreen
            case .ldc: return UIColor.systemCyan
            case .cdk: return FireTheme.uiAccent
            case .settings: return UIColor.systemGray
            }
        }
    }

    private let appViewModel: FireAppViewModel
    private let navigationState: FireNavigationState
    private let profileViewModel: FireProfileViewModel
    private let topicDetailStore: FireTopicDetailStore
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var cancellables: Set<AnyCancellable> = []
    private var isActive = false

    private var topicRoutePresenter: FireTopicRoutePresenter {
        FireTopicRoutePresenter { [weak self] route in
            guard let self, route.isTopicRoute else { return false }
            navigationState.presentTopicRoute(route)
            return true
        }
    }

    init(
        viewModel: FireAppViewModel,
        navigationState: FireNavigationState,
        profileViewModel: FireProfileViewModel,
        topicDetailStore: FireTopicDetailStore
    ) {
        self.appViewModel = viewModel
        self.navigationState = navigationState
        self.profileViewModel = profileViewModel
        self.topicDetailStore = topicDetailStore
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "我的"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = FireTheme.uiCanvas
        navigationController?.navigationBar.tintColor = FireTheme.uiAccent

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = FireTheme.uiCanvas
        tableView.separatorColor = FireTheme.uiDivider
        // Align past colored icon well (14 leading + 30 well + 12 gap ≈ 56).
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 56, bottom: 0, right: 0)
        // Pull the profile header up under the nav bar — insetGrouped defaults are too airy.
        tableView.sectionHeaderTopPadding = 0
        tableView.sectionFooterHeight = 6
        tableView.contentInset = UIEdgeInsets(top: 4, left: 0, bottom: 12, right: 0)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 48
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.register(FireProfileMenuRowCell.self, forCellReuseIdentifier: FireProfileMenuRowCell.reuseID)
        tableView.register(FireProfileHeaderTableCell.self, forCellReuseIdentifier: FireProfileHeaderTableCell.reuseID)
        tableView.refreshControl = UIRefreshControl()
        tableView.refreshControl?.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        bind()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isActive = navigationState.selectedTab == 2
        if isActive {
            profileViewModel.syncWithCurrentSession()
        }
        tableView.reloadData()
    }

    private func bind() {
        profileViewModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.tableView.reloadData()
                self?.tableView.refreshControl?.endRefreshing()
            }
            .store(in: &cancellables)

        navigationState.$selectedTab
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tab in
                guard let self else { return }
                self.isActive = tab == 2
                if self.isActive {
                    self.profileViewModel.syncWithCurrentSession()
                }
            }
            .store(in: &cancellables)
    }

    @objc
    private func handleRefresh() {
        Task { [weak self] in
            await self?.profileViewModel.refreshAll()
            self?.tableView.refreshControl?.endRefreshing()
        }
    }

    private var displayUsername: String {
        profileViewModel.currentUsername ?? appViewModel.session.profileDisplayName
    }

    private var displayName: String {
        let trimmed = profileViewModel.profile?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? displayUsername : trimmed
    }

    private var canLogout: Bool {
        appViewModel.session.hasLoginSession || appViewModel.session.readiness.canReadAuthenticatedApi
    }

    private func value(for social: SocialRow) -> String {
        switch social {
        case .following:
            return FireProfileFormat.number(profileViewModel.profile?.totalFollowing ?? 0)
        case .followers:
            return FireProfileFormat.number(profileViewModel.profile?.totalFollowers ?? 0)
        }
    }

    /// Trailing count only — no descriptive filler like “已保存”.
    private func value(for content: ContentRow) -> String? {
        switch content {
        case .bookmarks:
            let count = profileViewModel.summary?.stats.bookmarkCount ?? 0
            return "\(FireProfileFormat.number(count))条"
        case .badges:
            let count = UInt32(profileViewModel.summary?.badges.count ?? 0)
            return "\(FireProfileFormat.number(count))枚"
        case .activity, .history, .drafts, .messages:
            return nil
        }
    }

    private func openSettings() {
        FireMotionHaptics.selection()
        pushFullScreen(FireSettingsViewController(viewModel: appViewModel, canLogout: canLogout))
    }

    private func openSocial(_ row: SocialRow) {
        FireMotionHaptics.selection()
        let kind: FireFollowListViewModel.Kind = row == .following ? .following : .followers
        appViewModel.topicRouteLogger()?.info(
            "profile tab open follow list kind=\(kind.title) username_length=\(displayUsername.count)"
        )
        // UIKit follow list owns profile + topic drill-down. Do not host SwiftUI
        // NavigationLink for this path — environment presenters were no-ops after
        // follow list → public profile → 最近动态.
        let controller = FireFollowListViewController(
            viewModel: appViewModel,
            topicDetailStore: topicDetailStore,
            username: displayUsername,
            kind: kind,
            topicRoutePresenter: topicRoutePresenter
        )
        pushFullScreen(controller)
    }

    private func openContent(_ row: ContentRow) {
        FireMotionHaptics.selection()
        switch row {
        case .activity:
            pushHosting(
                FireProfileActivityTimelineView(
                    viewModel: appViewModel,
                    profileViewModel: profileViewModel,
                    topicDetailStore: topicDetailStore
                ),
                title: "我的动态"
            )
        case .bookmarks:
            pushFullScreen(
                FireBookmarksViewController(
                    viewModel: appViewModel,
                    topicDetailStore: topicDetailStore,
                    username: displayUsername,
                    topicRoutePresenter: topicRoutePresenter
                )
            )
        case .history:
            pushFullScreen(
                FireReadHistoryViewController(
                    viewModel: appViewModel,
                    topicDetailStore: topicDetailStore,
                    topicRoutePresenter: topicRoutePresenter
                )
            )
        case .drafts:
            pushFullScreen(FireDraftsViewController(viewModel: appViewModel))
        case .messages:
            pushFullScreen(
                FirePrivateMessagesViewController(
                    viewModel: appViewModel,
                    topicDetailStore: topicDetailStore,
                    topicRoutePresenter: topicRoutePresenter
                )
            )
        case .badges:
            pushHosting(FireMyBadgesView(badges: profileViewModel.summary?.badges ?? []), title: "我的勋章")
        }
    }

    private func openAccount(_ row: AccountRow) {
        FireMotionHaptics.selection()
        switch row {
        case .feedback:
            FireFeedbackPresenter.present(
                from: self,
                appViewModel: appViewModel,
                source: "profile"
            )
        case .invites:
            pushHosting(FireInviteLinksView(viewModel: appViewModel, username: displayUsername), title: "邀请链接")
        case .ldc:
            pushHosting(FireLDCView(viewModel: appViewModel), title: "LDC 信用")
        case .cdk:
            pushHosting(FireCDKView(viewModel: appViewModel), title: "CDK 连接")
        case .settings:
            openSettings()
        }
    }

    /// Full-screen secondary page above the tab shell (covers tab bar; does not hide it).
    private func pushFullScreen(_ controller: UIViewController) {
        controller.view.backgroundColor = controller.view.backgroundColor ?? FireTheme.uiCanvas
        FireRootCoordinator.presentSecondary(controller)
    }

    private func pushHosting<Content: View>(_ root: Content, title: String? = nil) {
        let host = FireHosting.controller(
            rootView: root
                .environmentObject(navigationState)
                .environmentObject(topicDetailStore)
                .fireTopicRoutePresenter(topicRoutePresenter)
                .navigationBarTitleDisplayMode(.inline),
            title: title
        )
        pushFullScreen(host)
    }

    private func applyGroupedChrome(to cell: UITableViewCell) {
        var background = UIBackgroundConfiguration.listGroupedCell()
        background.backgroundColor = FireTheme.uiSurface
        background.cornerRadius = FireTheme.cornerRadius
        cell.backgroundConfiguration = background
        cell.tintColor = FireTheme.uiTertiaryInk
    }

    private func configureMenuRow(
        _ cell: FireProfileMenuRowCell,
        systemImage: String,
        title: String,
        value: String? = nil,
        iconWellColor: UIColor
    ) {
        applyGroupedChrome(to: cell)
        cell.configure(
            systemImage: systemImage,
            title: title,
            value: value,
            iconWellColor: iconWellColor
        )
    }
}

extension FireProfileViewController: UITableViewDataSource, UITableViewDelegate {
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
        case .social:
            return SocialRow.allCases.count
        case .content:
            return ContentRow.allCases.count
        case .account:
            return AccountRow.allCases.count
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        switch section {
        case .social: return "社交"
        case .content: return "内容"
        case .account: return "账户"
        case .error, .header:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.textLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        header.textLabel?.textColor = FireTheme.uiTertiaryInk
        header.textLabel?.text = header.textLabel?.text?.uppercased()
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard let section = Section(rawValue: section) else { return 0 }
        switch section {
        case .error, .header:
            return CGFloat.leastNormalMagnitude
        case .social, .content, .account:
            return UITableView.automaticDimension
        }
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        guard let section = Section(rawValue: section) else { return 6 }
        switch section {
        case .error:
            return CGFloat.leastNormalMagnitude
        case .header:
            return 4
        case .social, .content, .account:
            return 6
        }
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        UIView()
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableView.automaticDimension
        }
        switch section {
        case .social, .content, .account:
            return FireProfileMenuRowCell.preferredHeight
        case .error, .header:
            return UITableView.automaticDimension
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }
        switch section {
        case .error:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            applyGroupedChrome(to: cell)
            var content = cell.defaultContentConfiguration()
            content.text = profileViewModel.errorMessage ?? appViewModel.errorMessage
            content.textProperties.color = FireTheme.uiError
            content.textProperties.font = .preferredFont(forTextStyle: .footnote)
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
                bio: profileViewModel.profile?.bioPlainText,
                trustLevel: profileViewModel.profile?.trustLevel,
                followers: profileViewModel.profile?.totalFollowers ?? 0,
                likes: profileViewModel.summary?.stats.likesReceived ?? 0,
                following: profileViewModel.profile?.totalFollowing ?? 0
            )
            return cell
        case .social:
            let row = SocialRow.allCases[indexPath.row]
            let cell = tableView.dequeueReusableCell(
                withIdentifier: FireProfileMenuRowCell.reuseID,
                for: indexPath
            ) as! FireProfileMenuRowCell
            configureMenuRow(
                cell,
                systemImage: row.systemImage,
                title: row.title,
                value: value(for: row),
                iconWellColor: row.iconWellColor
            )
            return cell
        case .content:
            let row = ContentRow.allCases[indexPath.row]
            let cell = tableView.dequeueReusableCell(
                withIdentifier: FireProfileMenuRowCell.reuseID,
                for: indexPath
            ) as! FireProfileMenuRowCell
            configureMenuRow(
                cell,
                systemImage: row.systemImage,
                title: row.title,
                value: value(for: row),
                iconWellColor: row.iconWellColor
            )
            return cell
        case .account:
            let row = AccountRow.allCases[indexPath.row]
            let cell = tableView.dequeueReusableCell(
                withIdentifier: FireProfileMenuRowCell.reuseID,
                for: indexPath
            ) as! FireProfileMenuRowCell
            configureMenuRow(
                cell,
                systemImage: row.systemImage,
                title: row.title,
                iconWellColor: row.iconWellColor
            )
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let section = Section(rawValue: indexPath.section) else { return }
        switch section {
        case .error, .header:
            break
        case .social:
            openSocial(SocialRow.allCases[indexPath.row])
        case .content:
            openContent(ContentRow.allCases[indexPath.row])
        case .account:
            openAccount(AccountRow.allCases[indexPath.row])
        }
    }
}
