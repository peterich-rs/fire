import Combine
import UIKit

@MainActor
final class FireChatViewController: UIViewController {
    private let viewModel: FireAppViewModel
    private let channelsStore: FireChatChannelsStore
    private var cancellables: Set<AnyCancellable> = []
    private var loadTask: Task<Void, Never>?

    private lazy var segmentControl: UISegmentedControl = {
        let control = UISegmentedControl(
            items: FireChatChannelsStore.Segment.allCases.map(\.title)
        )
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        return control
    }()

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.dataSource = self
        table.delegate = self
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 72
        table.separatorInset = UIEdgeInsets(top: 0, left: 72, bottom: 0, right: 0)
        table.register(FireChatChannelCell.self, forCellReuseIdentifier: FireChatChannelCell.reuseID)
        table.refreshControl = refreshControl
        return table
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        return control
    }()

    private lazy var emptyLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        label.isHidden = true
        return label
    }()

    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .medium)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.hidesWhenStopped = true
        return view
    }()

    init(viewModel: FireAppViewModel, channelsStore: FireChatChannelsStore) {
        self.viewModel = viewModel
        self.channelsStore = channelsStore
        super.init(nibName: nil, bundle: nil)
        title = "聊天"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = FireTheme.uiCanvas
        navigationItem.titleView = segmentControl
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "square.and.pencil"),
            style: .plain,
            target: self,
            action: #selector(openNewChat)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "新建聊天"

        view.addSubview(tableView)
        view.addSubview(emptyLabel)
        view.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        bindStore()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadTask = Task { [weak self] in
            await self?.channelsStore.loadIfNeeded()
        }
    }

    private func bindStore() {
        Publishers.CombineLatest4(
            channelsStore.$directMessageChannels,
            channelsStore.$publicChannels,
            channelsStore.$selectedSegment,
            channelsStore.$errorMessage
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, segment, _ in
            self?.segmentControl.selectedSegmentIndex = segment.rawValue
            self?.reloadUI()
        }
        .store(in: &cancellables)

        channelsStore.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                guard let self else { return }
                if isLoading, !self.channelsStore.hasLoadedOnce {
                    self.loadingIndicator.startAnimating()
                } else {
                    self.loadingIndicator.stopAnimating()
                }
                if !isLoading {
                    self.refreshControl.endRefreshing()
                }
            }
            .store(in: &cancellables)
    }

    private func reloadUI() {
        tableView.reloadData()
        let channels = channelsStore.displayedChannels
        if let error = channelsStore.errorMessage, channels.isEmpty {
            emptyLabel.text = "加载失败\n\(error)"
            emptyLabel.isHidden = false
        } else if channels.isEmpty, channelsStore.hasLoadedOnce {
            emptyLabel.text = channelsStore.selectedSegment == .directMessages
                ? "暂无私信\n点击右上角开始新对话"
                : "暂无公共频道\n加入频道后会出现在这里"
            emptyLabel.isHidden = false
        } else {
            emptyLabel.isHidden = true
        }
    }

    @objc private func segmentChanged() {
        let index = segmentControl.selectedSegmentIndex
        guard let segment = FireChatChannelsStore.Segment(rawValue: index) else { return }
        channelsStore.selectSegment(segment)
    }

    @objc private func pullToRefresh() {
        loadTask = Task { [weak self] in
            await self?.channelsStore.refresh()
        }
    }

    @objc private func openNewChat() {
        let alert = UIAlertController(
            title: "新建聊天",
            message: "输入对方用户名（多人用逗号分隔）",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "username"
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "开始", style: .default) { [weak self] _ in
            guard let self else { return }
            let raw = alert.textFields?.first?.text ?? ""
            let usernames = raw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !usernames.isEmpty else { return }
            Task { await self.createDirectMessage(usernames: usernames) }
        })
        present(alert, animated: true)
    }

    private func createDirectMessage(usernames: [String]) async {
        do {
            let channel = try await viewModel.createDirectMessageChannel(
                request: CreateDirectMessageChannelRequestState(
                    targetUsernames: usernames,
                    name: nil,
                    upsert: usernames.count == 1
                )
            )
            channelsStore.upsert(channel)
            openChannel(channel)
        } catch {
            let alert = UIAlertController(
                title: "无法创建聊天",
                message: error.localizedDescription,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "好", style: .default))
            present(alert, animated: true)
        }
    }

    private func openChannel(_ channel: ChatChannelState) {
        let controller = FireChatChannelViewController(
            channel: channel,
            viewModel: viewModel,
            onRead: { [weak self] channelID in
                self?.channelsStore.clearTracking(for: channelID)
            }
        )
        FireRootCoordinator.presentSecondary(controller)
    }
}

extension FireChatViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        channelsStore.displayedChannels.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: FireChatChannelCell.reuseID,
            for: indexPath
        ) as! FireChatChannelCell
        let channel = channelsStore.displayedChannels[indexPath.row]
        cell.configure(
            channel: channel,
            badge: channelsStore.badge(for: channel),
            baseURL: viewModel.bootstrapBaseURLString()
        )
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let channel = channelsStore.displayedChannels[indexPath.row]
        openChannel(channel)
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let channel = channelsStore.displayedChannels[indexPath.row]
        let markRead = UIContextualAction(style: .normal, title: "已读") { [weak self] _, _, done in
            Task {
                try? await self?.viewModel.markChatChannelRead(channelID: channel.id)
                self?.channelsStore.clearTracking(for: channel.id)
                done(true)
            }
        }
        markRead.backgroundColor = .systemBlue

        let leave = UIContextualAction(style: .destructive, title: "退出") { [weak self] _, _, done in
            Task {
                try? await self?.viewModel.leaveChatChannel(channelID: channel.id)
                await self?.channelsStore.refresh()
                done(true)
            }
        }
        return UISwipeActionsConfiguration(actions: [leave, markRead])
    }
}

private final class FireChatChannelCell: UITableViewCell {
    static let reuseID = "FireChatChannelCell"

    private let avatarView = FireTopicListAvatarView()
    private let titleLabel = UILabel()
    private let previewLabel = UILabel()
    private let badgeLabel = UILabel()
    private let timeLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default
        accessoryType = .disclosureIndicator

        avatarView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        previewLabel.font = .preferredFont(forTextStyle: .subheadline)
        previewLabel.textColor = .secondaryLabel
        previewLabel.numberOfLines = 1
        previewLabel.translatesAutoresizingMaskIntoConstraints = false

        timeLabel.font = .preferredFont(forTextStyle: .caption1)
        timeLabel.textColor = .tertiaryLabel
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        badgeLabel.font = .systemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .bold)
        badgeLabel.textColor = .white
        badgeLabel.backgroundColor = .systemRed
        badgeLabel.textAlignment = .center
        badgeLabel.layer.cornerRadius = 10
        badgeLabel.clipsToBounds = true
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.isHidden = true

        contentView.addSubview(avatarView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(previewLabel)
        contentView.addSubview(timeLabel)
        contentView.addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 44),
            avatarView.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -8),

            timeLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),

            previewLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            previewLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            previewLabel.trailingAnchor.constraint(lessThanOrEqualTo: badgeLabel.leadingAnchor, constant: -8),
            previewLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            badgeLabel.centerYAnchor.constraint(equalTo: previewLabel.centerYAnchor),
            badgeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            badgeLabel.heightAnchor.constraint(equalToConstant: 20),
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
    }

    func configure(channel: ChatChannelState, badge: UInt32, baseURL: String?) {
        titleLabel.text = channel.displayTitle
        previewLabel.text = channel.lastMessage?.previewText.isEmpty == false
            ? channel.lastMessage?.previewText
            : (channel.description ?? "暂无消息")
        timeLabel.text = relativeTime(from: channel.lastMessage?.createdAt)
        if badge > 0 {
            badgeLabel.isHidden = false
            badgeLabel.text = badge > 99 ? " 99+ " : " \(badge) "
        } else {
            badgeLabel.isHidden = true
        }

        let base = baseURL ?? "https://linux.do"
        let peer = channel.dmUsers.first
        let username = peer?.username.isEmpty == false
            ? peer!.username
            : channel.displayTitle
        avatarView.configure(
            username: username,
            avatarTemplate: peer?.avatarTemplate,
            baseURLString: base
        )
    }

    private func relativeTime(from value: String?) -> String {
        guard let value, let date = FireChatTime.parse(value) else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
