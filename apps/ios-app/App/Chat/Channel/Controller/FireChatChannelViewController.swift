import PhotosUI
import UIKit

@MainActor
final class FireChatChannelViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    let viewModel: FireAppViewModel
    let onRead: (UInt64) -> Void
    let session: FireChatChannelSession
    var channel: ChatChannelState
    let threadID: UInt64?
    var messages: [ChatMessageState] = []
    var pins: [ChatMessageState] = []
    var canLoadMorePast = false
    var isSending = false

    lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.dataSource = self
        table.delegate = self
        table.separatorStyle = .none
        table.keyboardDismissMode = .interactive
        table.backgroundColor = FireTheme.uiCanvas
        table.contentInsetAdjustmentBehavior = .never
        table.register(FireChatMessageCell.self, forCellReuseIdentifier: FireChatMessageCell.reuseID)
        // Discord-style chronological stream (oldest → newest, newest near input).
        return table
    }()

    lazy var pinBanner: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = FireTheme.uiSurfaceSecondary
        button.contentHorizontalAlignment = .left
        button.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        config.baseForegroundColor = FireTheme.uiInk
        button.configuration = config
        button.addTarget(self, action: #selector(pinBannerTapped), for: .touchUpInside)
        button.isHidden = true
        return button
    }()

    /// WeChat-style opaque full-width bottom strip (mirrors topic quick-reply bar).
    lazy var inputBar: FireBottomInputBar = {
        let bar = FireBottomInputBar(kind: .chat)
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.callbacks = .init(
            onTextChanged: { _ in },
            onSend: { [weak self] payload in
                Task { await self?.send(payload: payload) }
            },
            onLeadingAction: { [weak self] in
                self?.presentImagePicker()
            },
            onFocusChanged: { _ in },
            onHeightChanged: { [weak self] _ in
                self?.handleInputHeightChanged()
            },
            onSearchMentions: { [weak self] term in
                await self?.searchChatMentions(term: term) ?? []
            },
            onPickImage: { [weak self] in
                self?.presentImagePicker()
            }
        )
        return bar
    }()

    var composerBottomConstraint: NSLayoutConstraint?
    let isThread: Bool

    init(
        channel: ChatChannelState,
        viewModel: FireAppViewModel,
        threadID: UInt64? = nil,
        onRead: @escaping (UInt64) -> Void
    ) {
        self.channel = channel
        self.viewModel = viewModel
        self.threadID = threadID
        self.isThread = threadID != nil
        self.onRead = onRead
        session = FireChatChannelSession(
            channel: channel,
            viewModel: viewModel,
            threadID: threadID
        )
        super.init(nibName: nil, bundle: nil)
        title = isThread ? "消息串" : channel.displayTitle
        session.onChange = { [weak self] snapshot, change in
            self?.applySessionSnapshot(snapshot, change: change)
        }
        session.onRead = onRead
        session.onError = { [weak self] error in
            self?.presentError(error)
        }
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
        Task { [weak self] in
            await self?.session.open()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateDismissButtonIfNeeded()
    }

    func updateDismissButtonIfNeeded() {
        let isRootPresentedChat =
            navigationController?.presentingViewController != nil
            && navigationController?.viewControllers.count == 1
        if isRootPresentedChat {
            let dismissAction = UIAction { [weak self] _ in
                self?.navigationController?.dismiss(animated: true)
            }
            let dismissItem = UIBarButtonItem(
                title: "返回",
                image: UIImage(systemName: "chevron.backward"),
                primaryAction: dismissAction
            )
            dismissItem.accessibilityLabel = "返回"
            navigationItem.leftBarButtonItem = dismissItem
        } else {
            navigationItem.leftBarButtonItem = nil
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        let session = session
        Task { @MainActor in
            session.close()
        }
    }

    func setupLayout() {
        view.addSubview(pinBanner)
        view.addSubview(tableView)
        view.addSubview(inputBar)

        let bottom = inputBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        composerBottomConstraint = bottom

        NSLayoutConstraint.activate([
            pinBanner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            pinBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pinBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottom,

            tableView.topAnchor.constraint(equalTo: pinBanner.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: inputBar.topAnchor),
        ])
    }

    func updatePinBanner() {
        guard !isThread, let pin = pins.first else {
            pinBanner.isHidden = true
            return
        }
        pinBanner.isHidden = false
        let text = pin.previewText.isEmpty ? "置顶消息" : "置顶：\(pin.previewText)"
        pinBanner.setTitle(text, for: .normal)
    }

    @objc func pinBannerTapped() {
        guard let pin = pins.first else { return }
        if let index = messages.firstIndex(where: { $0.id == pin.id }) {
            tableView.scrollToRow(at: IndexPath(row: index, section: 0), at: .middle, animated: true)
        }
    }

    func handleInputHeightChanged() {
        view.layoutIfNeeded()
        if isNearBottom() {
            scrollToBottom(animated: false)
        }
    }

    @objc func keyboardWillChange(_ notification: Notification) {
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

    func presentError(_ error: Error) {
        let alert = UIAlertController(
            title: "操作失败",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}
