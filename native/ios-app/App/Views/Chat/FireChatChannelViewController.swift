import UIKit

@MainActor
final class FireChatChannelViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextViewDelegate {
    private let viewModel: FireAppViewModel
    private let onRead: (UInt64) -> Void
    private var channel: ChatChannelState
    private var messages: [ChatMessageState] = []
    private var canLoadMorePast = false
    private var isLoading = false
    private var isSending = false

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.dataSource = self
        table.delegate = self
        table.separatorStyle = .none
        table.keyboardDismissMode = .interactive
        table.register(FireChatMessageCell.self, forCellReuseIdentifier: FireChatMessageCell.reuseID)
        table.transform = CGAffineTransform(scaleX: 1, y: -1)
        return table
    }()

    private lazy var composerContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = FireTheme.uiSurface
        return view
    }()

    private lazy var textView: UITextView = {
        let view = UITextView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.font = .preferredFont(forTextStyle: .body)
        view.layer.cornerRadius = FireTheme.smallCornerRadius
        view.backgroundColor = FireTheme.uiSurfaceSecondary
        view.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        view.delegate = self
        view.isScrollEnabled = false
        return view
    }()

    private lazy var sendButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        button.tintColor = FireTheme.uiAccent
        button.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        button.accessibilityLabel = "发送"
        return button
    }()

    private var textViewHeightConstraint: NSLayoutConstraint?
    private var composerBottomConstraint: NSLayoutConstraint?

    init(
        channel: ChatChannelState,
        viewModel: FireAppViewModel,
        onRead: @escaping (UInt64) -> Void
    ) {
        self.channel = channel
        self.viewModel = viewModel
        self.onRead = onRead
        super.init(nibName: nil, bundle: nil)
        title = channel.displayTitle
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = FireTheme.uiCanvas
        setupLayout()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        Task { await loadInitial() }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupLayout() {
        view.addSubview(tableView)
        view.addSubview(composerContainer)
        composerContainer.addSubview(textView)
        composerContainer.addSubview(sendButton)

        let height = textView.heightAnchor.constraint(equalToConstant: 36)
        textViewHeightConstraint = height
        let bottom = composerContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        composerBottomConstraint = bottom

        NSLayoutConstraint.activate([
            composerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            composerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottom,

            textView.leadingAnchor.constraint(equalTo: composerContainer.leadingAnchor, constant: 12),
            textView.topAnchor.constraint(equalTo: composerContainer.topAnchor, constant: 8),
            textView.bottomAnchor.constraint(equalTo: composerContainer.bottomAnchor, constant: -8),
            textView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            height,

            sendButton.trailingAnchor.constraint(equalTo: composerContainer.trailingAnchor, constant: -12),
            sendButton.centerYAnchor.constraint(equalTo: textView.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 36),
            sendButton.heightAnchor.constraint(equalToConstant: 36),

            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: composerContainer.topAnchor),
        ])
    }

    private func loadInitial() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let refreshed = try await viewModel.fetchChatChannel(channelID: channel.id)
            channel = refreshed
            title = refreshed.displayTitle
            let page = try await viewModel.fetchChatMessages(
                query: ChatMessagesQueryState(
                    channelId: channel.id,
                    direction: nil,
                    targetMessageId: nil,
                    fetchFromLastRead: true,
                    pageSize: 50
                )
            )
            messages = page.messages.reversed()
            canLoadMorePast = page.canLoadMorePast
            tableView.reloadData()
            if let latest = page.messages.last?.id {
                try? await viewModel.markChatChannelRead(channelID: channel.id, messageID: latest)
                onRead(channel.id)
            }
        } catch {
            presentError(error)
        }
    }

    private func loadMorePast() async {
        guard canLoadMorePast, !isLoading, let oldest = messages.last else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await viewModel.fetchChatMessages(
                query: ChatMessagesQueryState(
                    channelId: channel.id,
                    direction: "past",
                    targetMessageId: oldest.id,
                    fetchFromLastRead: false,
                    pageSize: 50
                )
            )
            let older = page.messages.reversed()
            messages.append(contentsOf: older)
            canLoadMorePast = page.canLoadMorePast
            tableView.reloadData()
        } catch {
            presentError(error)
        }
    }

    @objc private func sendTapped() {
        let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        sendButton.isEnabled = false
        Task {
            defer {
                isSending = false
                sendButton.isEnabled = true
            }
            do {
                _ = try await viewModel.sendChatMessage(
                    request: SendChatMessageRequestState(
                        channelId: channel.id,
                        message: text,
                        stagedId: UUID().uuidString,
                        inReplyToId: nil,
                        threadId: nil,
                        uploadIds: []
                    )
                )
                textView.text = ""
                textViewDidChange(textView)
                let page = try await viewModel.fetchChatMessages(
                    query: ChatMessagesQueryState(
                        channelId: channel.id,
                        direction: nil,
                        targetMessageId: nil,
                        fetchFromLastRead: false,
                        pageSize: 50
                    )
                )
                messages = page.messages.reversed()
                canLoadMorePast = page.canLoadMorePast
                tableView.reloadData()
                if let latest = page.messages.last?.id {
                    try? await viewModel.markChatChannelRead(channelID: channel.id, messageID: latest)
                    onRead(channel.id)
                }
            } catch {
                presentError(error)
            }
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        let size = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude))
        textViewHeightConstraint?.constant = min(max(size.height, 36), 120)
        textView.isScrollEnabled = size.height > 120
    }

    @objc private func keyboardWillChange(_ notification: Notification) {
        guard
            let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
            let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        else {
            return
        }
        let converted = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.maxY - converted.minY - view.safeAreaInsets.bottom)
        composerBottomConstraint?.constant = -overlap
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }

    private func presentError(_ error: Error) {
        let alert = UIAlertController(
            title: "操作失败",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: FireChatMessageCell.reuseID,
            for: indexPath
        ) as! FireChatMessageCell
        let message = messages[indexPath.row]
        cell.configure(message: message)
        cell.transform = CGAffineTransform(scaleX: 1, y: -1)
        return cell
    }

    func tableView(
        _ tableView: UITableView,
        willDisplay cell: UITableViewCell,
        forRowAt indexPath: IndexPath
    ) {
        if indexPath.row >= messages.count - 3 {
            Task { await loadMorePast() }
        }
    }
}

private final class FireChatMessageCell: UITableViewCell {
    static let reuseID = "FireChatMessageCell"

    private let bubble = UIView()
    private let authorLabel = UILabel()
    private let bodyLabel = UILabel()
    private let metaLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.backgroundColor = FireTheme.uiSurface
        bubble.layer.cornerRadius = FireTheme.mediumCornerRadius

        authorLabel.translatesAutoresizingMaskIntoConstraints = false
        authorLabel.font = .preferredFont(forTextStyle: .caption1)
        authorLabel.textColor = FireTheme.uiAccent

        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.font = .preferredFont(forTextStyle: .body)
        bodyLabel.numberOfLines = 0

        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        metaLabel.font = .preferredFont(forTextStyle: .caption2)
        metaLabel.textColor = .tertiaryLabel

        contentView.addSubview(bubble)
        bubble.addSubview(authorLabel)
        bubble.addSubview(bodyLabel)
        bubble.addSubview(metaLabel)

        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            bubble.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            bubble.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -48),
            bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),

            authorLabel.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            authorLabel.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
            authorLabel.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),

            bodyLabel.topAnchor.constraint(equalTo: authorLabel.bottomAnchor, constant: 4),
            bodyLabel.leadingAnchor.constraint(equalTo: authorLabel.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: authorLabel.trailingAnchor),

            metaLabel.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 4),
            metaLabel.leadingAnchor.constraint(equalTo: authorLabel.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: authorLabel.trailingAnchor),
            metaLabel.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(message: ChatMessageState) {
        if message.isDeleted {
            authorLabel.text = message.user?.username ?? "用户"
            bodyLabel.text = "消息已删除"
            bodyLabel.textColor = .secondaryLabel
        } else {
            authorLabel.text = message.user?.username ?? "用户"
            bodyLabel.text = message.message.isEmpty ? message.previewText : message.message
            bodyLabel.textColor = .label
        }
        var meta: [String] = []
        if let created = message.createdAt, let date = FireChatTime.parse(created) {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            meta.append(formatter.string(from: date))
        }
        if message.edited {
            meta.append("已编辑")
        }
        if !message.reactions.isEmpty {
            let reactionText = message.reactions
                .map { ":\($0.emoji): \($0.count)" }
                .joined(separator: " ")
            meta.append(reactionText)
        }
        metaLabel.text = meta.joined(separator: " · ")
    }
}
