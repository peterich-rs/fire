import Combine
import SnapKit
import SwiftUI
import UIKit

/// UIKit profile tab hub using the unified black-canvas + elevated-card language.
@MainActor
final class FireProfileViewController: UIViewController {
    enum Section: Int, CaseIterable {
        case error
        case header
        case social
        case content
        case account
    }

    enum SocialRow: Int, CaseIterable {
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

    enum ContentRow: Int, CaseIterable {
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

    enum AccountRow: Int, CaseIterable {
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

    let appViewModel: FireAppViewModel
    let navigationState: FireNavigationState
    let profileViewModel: FireProfileViewModel
    let topicDetailStore: FireTopicDetailStore
    let tableView = UITableView(frame: .zero, style: .insetGrouped)
    var cancellables: Set<AnyCancellable> = []
    var isActive = false

    var topicRoutePresenter: FireTopicRoutePresenter {
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

    /// Trailing count only — no descriptive filler like “已保存”.
    /// Full-screen secondary page above the tab shell (covers tab bar; does not hide it).
}
