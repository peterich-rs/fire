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
        case activity
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
            case .following: return "person.2"
            case .followers: return "person.2.fill"
            }
        }
    }

    private enum ContentRow: Int, CaseIterable {
        case bookmarks
        case history
        case drafts
        case messages
        case badges

        var title: String {
            switch self {
            case .bookmarks: return "我的书签"
            case .history: return "浏览历史"
            case .drafts: return "草稿箱"
            case .messages: return "私信"
            case .badges: return "我的勋章"
            }
        }

        var systemImage: String {
            switch self {
            case .bookmarks: return "bookmark.fill"
            case .history: return "clock.arrow.trianglehead.counterclockwise.rotate.90"
            case .drafts: return "tray.full.fill"
            case .messages: return "tray.2.fill"
            case .badges: return "rosette"
            }
        }
    }

    private enum AccountRow: Int, CaseIterable {
        case invites
        case ldc
        case cdk
        case settings

        var title: String {
            switch self {
            case .invites: return "邀请链接"
            case .ldc: return "LDC 信用"
            case .cdk: return "CDK 连接"
            case .settings: return "设置"
            }
        }

        var systemImage: String {
            switch self {
            case .invites: return "ticket.fill"
            case .ldc: return "creditcard.fill"
            case .cdk: return "key.fill"
            case .settings: return "gearshape.fill"
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

    private var recentActions: [UserActionState] {
        Array(profileViewModel.actions.prefix(3))
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

    private func subtitle(for content: ContentRow) -> String? {
        switch content {
        case .bookmarks:
            let count = profileViewModel.summary?.stats.bookmarkCount ?? 0
            return count > 0 ? "已保存 \(FireProfileFormat.number(count)) 条" : nil
        case .badges:
            let count = UInt32(profileViewModel.summary?.badges.count ?? 0)
            return count > 0 ? "\(FireProfileFormat.number(count)) 枚" : nil
        case .history, .drafts, .messages:
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
        pushHosting(
            FireFollowListView(viewModel: appViewModel, username: displayUsername, kind: kind)
                .fireTopicRoutePresenter(topicRoutePresenter)
        )
    }

    private func openContent(_ row: ContentRow) {
        FireMotionHaptics.selection()
        switch row {
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

    /// Full-screen independent page: hides tab bar, owns navigation chrome.
    private func pushFullScreen(_ controller: UIViewController) {
        controller.hidesBottomBarWhenPushed = true
        controller.view.backgroundColor = controller.view.backgroundColor ?? FireTheme.uiCanvas
        navigationController?.setNavigationBarHidden(false, animated: true)
        navigationController?.pushViewController(controller, animated: true)
    }

    private func pushHosting<Content: View>(_ root: Content, title: String? = nil) {
        let host = UIHostingController(
            rootView: root
                .environmentObject(navigationState)
                .environmentObject(topicDetailStore)
                .fireTopicRoutePresenter(topicRoutePresenter)
                .navigationBarTitleDisplayMode(.inline)
        )
        host.view.backgroundColor = FireTheme.uiCanvas
        if let title {
            host.title = title
            host.navigationItem.title = title
        }
        pushFullScreen(host)
    }

    private func presentTopic(for action: UserActionState) {
        guard let route = FireAppRoute.topic(action: action) else { return }
        _ = topicRoutePresenter.present(route)
    }

    private func applyGroupedChrome(to cell: UITableViewCell) {
        var background = UIBackgroundConfiguration.listGroupedCell()
        background.backgroundColor = FireTheme.uiSurface
        cell.backgroundConfiguration = background
        cell.tintColor = FireTheme.uiTertiaryInk
    }

    private func configureIconRow(
        _ cell: UITableViewCell,
        systemImage: String,
        title: String,
        subtitle: String? = nil,
        value: String? = nil
    ) {
        applyGroupedChrome(to: cell)
        var content = cell.defaultContentConfiguration()
        content.image = UIImage(systemName: systemImage)
        content.imageProperties.tintColor = FireTheme.uiInk
        content.imageProperties.preferredSymbolConfiguration = .init(pointSize: 15, weight: .semibold)
        content.imageProperties.cornerRadius = FireTheme.iconWellCornerRadius
        content.text = title
        content.textProperties.color = FireTheme.uiInk
        content.textProperties.font = .preferredFont(forTextStyle: .body)
        if let subtitle, !subtitle.isEmpty {
            content.secondaryText = subtitle
            content.secondaryTextProperties.color = FireTheme.uiSubtleInk
        } else if let value, !value.isEmpty {
            content.secondaryText = value
            content.secondaryTextProperties.color = FireTheme.uiTertiaryInk
        }
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
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
        case .activity:
            if !profileViewModel.hasLoadedActionsOnce {
                return 1
            }
            if recentActions.isEmpty {
                return 2
            }
            return recentActions.count + 1
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        switch section {
        case .social: return "社交"
        case .content: return "内容"
        case .account: return "账户"
        case .activity:
            return profileViewModel.selectedTab == .all ? "最近动态" : "最近\(profileViewModel.selectedTab.title)"
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
                bio: profileViewModel.profile?.bioCooked.flatMap { FireProfileFormat.plainText(fromHTML: $0) },
                trustLevel: profileViewModel.profile?.trustLevel,
                followers: profileViewModel.profile?.totalFollowers ?? 0,
                likes: profileViewModel.summary?.stats.likesReceived ?? 0,
                following: profileViewModel.profile?.totalFollowing ?? 0
            )
            return cell
        case .social:
            let row = SocialRow.allCases[indexPath.row]
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            configureIconRow(
                cell,
                systemImage: row.systemImage,
                title: row.title,
                value: value(for: row)
            )
            return cell
        case .content:
            let row = ContentRow.allCases[indexPath.row]
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            configureIconRow(
                cell,
                systemImage: row.systemImage,
                title: row.title,
                subtitle: subtitle(for: row)
            )
            return cell
        case .account:
            let row = AccountRow.allCases[indexPath.row]
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            configureIconRow(
                cell,
                systemImage: row.systemImage,
                title: row.title
            )
            return cell
        case .activity:
            if !profileViewModel.hasLoadedActionsOnce {
                let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
                applyGroupedChrome(to: cell)
                var content = cell.defaultContentConfiguration()
                if let error = profileViewModel.actionsErrorMessage {
                    content.text = error
                    content.textProperties.color = FireTheme.uiError
                } else {
                    content.text = "正在加载动态…"
                    content.textProperties.color = FireTheme.uiSubtleInk
                }
                cell.contentConfiguration = content
                cell.selectionStyle = .none
                return cell
            }
            if recentActions.isEmpty && indexPath.row == 0 {
                let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
                applyGroupedChrome(to: cell)
                var content = cell.defaultContentConfiguration()
                content.text = "还没有可展示的动态"
                content.textProperties.color = FireTheme.uiTertiaryInk
                content.textProperties.alignment = .center
                cell.contentConfiguration = content
                cell.selectionStyle = .none
                return cell
            }
            let seeAllRow = recentActions.isEmpty ? 1 : recentActions.count
            if indexPath.row == seeAllRow {
                let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
                configureIconRow(
                    cell,
                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    title: "查看全部动态"
                )
                return cell
            }
            let action = recentActions[indexPath.row]
            let cell = tableView.dequeueReusableCell(
                withIdentifier: FireProfileActivityTableCell.reuseID,
                for: indexPath
            ) as! FireProfileActivityTableCell
            applyGroupedChrome(to: cell)
            cell.configure(action: action)
            cell.accessoryType = FireAppRoute.topic(action: action) == nil ? .none : .disclosureIndicator
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
        case .activity:
            if !profileViewModel.hasLoadedActionsOnce {
                if profileViewModel.actionsErrorMessage != nil {
                    profileViewModel.loadActions(reset: true)
                }
                return
            }
            let seeAllRow = recentActions.isEmpty ? 1 : recentActions.count
            if indexPath.row == seeAllRow {
                pushHosting(
                    FireProfileActivityTimelineView(
                        viewModel: appViewModel,
                        profileViewModel: profileViewModel
                    ),
                    title: "全部动态"
                )
                return
            }
            guard indexPath.row < recentActions.count else { return }
            presentTopic(for: recentActions[indexPath.row])
        }
    }
}

// MARK: - Header

final class FireProfileHeaderTableCell: UITableViewCell {
    static let reuseID = "FireProfileHeaderTableCell"

    private let avatarView = FireTopicListAvatarView()
    private let nameLabel = UILabel()
    private let usernameLabel = UILabel()
    private let bioLabel = UILabel()
    private let statsLabel = UILabel()
    private let stack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        var background = UIBackgroundConfiguration.listGroupedCell()
        background.backgroundColor = FireTheme.uiSurface
        backgroundConfiguration = background

        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        let top = UIStackView(arrangedSubviews: [avatarView, {
            let v = UIStackView(arrangedSubviews: [nameLabel, usernameLabel, bioLabel])
            v.axis = .vertical
            v.spacing = 6
            return v
        }()])
        top.axis = .horizontal
        top.alignment = .top
        top.spacing = 14

        nameLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        nameLabel.numberOfLines = 2
        nameLabel.textColor = FireTheme.uiInk
        usernameLabel.font = .preferredFont(forTextStyle: .subheadline)
        usernameLabel.textColor = FireTheme.uiSubtleInk
        bioLabel.font = .preferredFont(forTextStyle: .footnote)
        bioLabel.textColor = FireTheme.uiSubtleInk
        bioLabel.numberOfLines = 3
        statsLabel.font = .preferredFont(forTextStyle: .footnote)
        statsLabel.textColor = FireTheme.uiSubtleInk
        statsLabel.numberOfLines = 1

        stack.addArrangedSubview(top)
        stack.addArrangedSubview(statsLabel)
        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 64),
            avatarView.heightAnchor.constraint(equalToConstant: 64),
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor, constant: -10),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        displayName: String,
        username: String,
        avatarTemplate: String?,
        bio: String?,
        trustLevel: UInt32?,
        followers: UInt32,
        likes: UInt32,
        following: UInt32
    ) {
        avatarView.configure(username: username, avatarTemplate: avatarTemplate, baseURLString: "https://linux.do")
        nameLabel.text = displayName
        usernameLabel.text = "@\(username)" + (trustLevel.map { " · TL\($0)" } ?? "")
        bioLabel.text = bio
        bioLabel.isHidden = (bio?.isEmpty ?? true)
        statsLabel.text = "\(FireProfileFormat.number(followers)) 粉丝 · \(FireProfileFormat.number(likes)) 获赞 · \(FireProfileFormat.number(following)) 关注"
    }
}

// MARK: - Activity

final class FireProfileActivityTableCell: UITableViewCell {
    static let reuseID = "FireProfileActivityTableCell"

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
        textLabel?.numberOfLines = 2
        textLabel?.textColor = FireTheme.uiInk
        detailTextLabel?.textColor = FireTheme.uiSubtleInk
        detailTextLabel?.numberOfLines = 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(action: UserActionState) {
        let excerpt = action.excerpt.flatMap { FireProfileFormat.plainText(fromHTML: $0) }
        textLabel?.text = (excerpt?.isEmpty == false ? excerpt : nil)
            ?? action.title
            ?? "动态 #\(action.actionType)"
        detailTextLabel?.text = action.createdAt.map { FireProfileFormat.relativeTime($0) }
    }
}

enum FireProfileFormat {
    static func number(_ value: UInt32) -> String {
        if value >= 10_000 { return String(format: "%.1fw", Double(value) / 10_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }

    static func relativeTime(_ isoDate: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: isoDate) ?? {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: isoDate)
        }()
        guard let date else { return isoDate }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    static func plainText(fromHTML rawHtml: String) -> String {
        guard let data = rawHtml.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
              )
        else {
            return rawHtml
        }
        return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
