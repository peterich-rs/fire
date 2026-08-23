import UIKit

enum FireUserCardChrome {
    static let compactDetentIdentifier = UISheetPresentationController.Detent.Identifier("fire.user-card.compact")
    static let compactDetentHeight: CGFloat = 292
    static let actionContentInsets = NSDirectionalEdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10)
    static let actionTitleFont = UIFont.systemFont(ofSize: 13, weight: .semibold)
    static let actionSymbolSize: CGFloat = 12
}

@MainActor
enum FireUserCard {
    static func present(
        from host: UIViewController,
        viewModel: FireAppViewModel,
        username: String
    ) {
        let card = FireUserCardViewController(viewModel: viewModel, username: username)
        card.modalPresentationStyle = .pageSheet
        if let sheet = card.sheetPresentationController {
            let compact = UISheetPresentationController.Detent.custom(
                identifier: FireUserCardChrome.compactDetentIdentifier
            ) { context in
                min(FireUserCardChrome.compactDetentHeight, context.maximumDetentValue)
            }
            sheet.detents = [compact, .large()]
            sheet.selectedDetentIdentifier = FireUserCardChrome.compactDetentIdentifier
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            sheet.preferredCornerRadius = 16
        }
        host.present(card, animated: true)
    }
}

@MainActor
final class FireUserCardViewController: UIViewController {
    private let appViewModel: FireAppViewModel
    private let username: String

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let avatarView = FireTopicListAvatarView()
    private let nameLabel = UILabel()
    private let handleLabel = UILabel()
    private let bioLabel = UILabel()
    private let metaLabel = UILabel()
    private let statusLabel = UILabel()
    private let actionsStack = UIStackView()
    private let loadingView = UIActivityIndicatorView(style: .medium)

    private var profile: UserProfileState?
    private var summary: UserSummaryState?

    init(viewModel: FireAppViewModel, username: String) {
        self.appViewModel = viewModel
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = FireTheme.uiCanvas
        configureLayout()
        Task { await load() }
    }

    private func configureLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
        ])

        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 12
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.layer.cornerRadius = 26
        avatarView.clipsToBounds = true
        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 52),
            avatarView.heightAnchor.constraint(equalToConstant: 52),
        ])
        let titles = UIStackView(arrangedSubviews: [nameLabel, handleLabel])
        titles.axis = .vertical
        titles.spacing = 3
        header.addArrangedSubview(avatarView)
        header.addArrangedSubview(titles)

        nameLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        nameLabel.textColor = FireTheme.uiInk
        handleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        handleLabel.textColor = FireTheme.uiTertiaryInk
        bioLabel.font = .systemFont(ofSize: 14, weight: .regular)
        bioLabel.textColor = FireTheme.uiSubtleInk
        bioLabel.numberOfLines = 3
        metaLabel.font = .systemFont(ofSize: 12, weight: .regular)
        metaLabel.textColor = FireTheme.uiTertiaryInk
        metaLabel.numberOfLines = 2
        statusLabel.font = .systemFont(ofSize: 13, weight: .regular)
        statusLabel.textColor = FireTheme.uiTertiaryInk
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center

        actionsStack.axis = .horizontal
        actionsStack.alignment = .fill
        actionsStack.distribution = .fillEqually
        actionsStack.spacing = 8

        loadingView.hidesWhenStopped = true
        stack.addArrangedSubview(header)
        stack.addArrangedSubview(metaLabel)
        stack.addArrangedSubview(bioLabel)
        stack.addArrangedSubview(actionsStack)
        stack.addArrangedSubview(statusLabel)
        stack.addArrangedSubview(loadingView)
        nameLabel.text = username
        handleLabel.text = "@\(username)"
        rebuildActions(canMessage: true, isOwnProfile: false)
    }

    private func rebuildActions(canMessage: Bool, isOwnProfile: Bool) {
        actionsStack.arrangedSubviews.forEach { view in
            actionsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        actionsStack.addArrangedSubview(
            makeButton(title: "主页", symbol: "person", filled: false, action: #selector(openProfile))
        )
        if !isOwnProfile {
            if canMessage {
                actionsStack.addArrangedSubview(
                    makeButton(title: "私信", symbol: "envelope", filled: false, action: #selector(openPrivateMessage))
                )
            }
            actionsStack.addArrangedSubview(
                makeButton(title: "聊天", symbol: "bubble.left", filled: true, action: #selector(openChat))
            )
        }
    }

    private func makeButton(title: String, symbol: String, filled: Bool, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        var config = filled ? UIButton.Configuration.filled() : UIButton.Configuration.gray()
        config.title = title
        config.image = UIImage(systemName: symbol)
        config.imagePadding = 4
        config.imagePlacement = .leading
        config.cornerStyle = .medium
        config.contentInsets = FireUserCardChrome.actionContentInsets
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: FireUserCardChrome.actionSymbolSize,
            weight: .semibold
        )
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = FireUserCardChrome.actionTitleFont
            return outgoing
        }
        button.configuration = config
        button.tintColor = FireTheme.uiAccent
        button.addTarget(self, action: action, for: .touchUpInside)
        button.fireBindPressBounce(.compact)
        return button
    }

    private func load() async {
        loadingView.startAnimating()
        statusLabel.text = nil
        do {
            let profile = try await appViewModel.fetchUserProfile(username: username)
            let summary = try? await appViewModel.fetchUserSummary(username: username)
            self.profile = profile
            self.summary = summary
            apply(profile: profile, summary: summary)
        } catch {
            statusLabel.text = error.localizedDescription
        }
        loadingView.stopAnimating()
    }

    private func apply(profile: UserProfileState, summary: UserSummaryState?) {
        let display = profile.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        nameLabel.text = (display?.isEmpty == false ? display : profile.username)
        handleLabel.text = "@\(profile.username) · \(profile.trustLevelLabel)"
        avatarView.configure(
            username: profile.username,
            avatarTemplate: profile.avatarTemplate,
            baseURLString: appViewModel.bootstrapBaseURLString() ?? "https://linux.do"
        )
        let stats = [
            "话题 \(summary?.stats.topicCount ?? 0)",
            "回复 \(summary?.stats.postCount ?? 0)",
            "获赞 \(summary?.stats.likesReceived ?? 0)",
            "粉丝 \(profile.totalFollowers)",
        ]
        var meta: [String] = [stats.joined(separator: " · ")]
        if let joined = humanize(profile.createdAt) {
            meta.append("加入 \(joined)")
        }
        if let seen = humanize(profile.lastSeenAt) {
            meta.append("最近活跃 \(seen)")
        }
        metaLabel.text = meta.joined(separator: "\n")
        if let bio = profile.bioCooked, !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bioLabel.text = plainTextFromHtml(rawHtml: bio)
            bioLabel.isHidden = false
        } else {
            bioLabel.isHidden = true
        }
        rebuildActions(canMessage: canMessage(profile), isOwnProfile: isOwnProfile(profile))
    }

    @objc private func openProfile() {
        let username = profile?.username ?? username
        dismiss(animated: true) {
            FireRootCoordinator.presentSecondaryRoute(.profile(username: username))
        }
    }

    @objc private func openPrivateMessage() {
        guard let profile,
              canMessage(profile) else {
            statusLabel.text = "无法向该用户发送私信。"
            return
        }
        dismiss(animated: true) { [appViewModel] in
            let composer = FireComposerViewController(
                viewModel: appViewModel,
                route: FireComposerRoute(kind: .privateMessage(recipients: [profile.username], title: nil)),
                onPrivateMessageCreated: { topicID, title in
                    FireRootCoordinator.presentSecondaryRoute(.topic(
                        topicId: topicID,
                        postNumber: nil,
                        preview: FireTopicRoutePreview.fromMetadata(title: title, slug: nil)
                    ))
                }
            )
            FireRootCoordinator.presentSecondary(composer)
        }
    }

    @objc private func openChat() {
        let target = profile?.username ?? username
        Task {
            do {
                let channel = try await appViewModel.createDirectMessageChannel(
                    request: CreateDirectMessageChannelRequestState(
                        targetUsernames: [target],
                        name: nil,
                        upsert: true
                    )
                )
                dismiss(animated: true) { [appViewModel] in
                    let controller = FireChatChannelViewController(
                        channel: channel,
                        viewModel: appViewModel,
                        onRead: { _ in }
                    )
                    FireRootCoordinator.presentSecondary(controller)
                }
            } catch {
                statusLabel.text = error.localizedDescription
            }
        }
    }

    private func isOwnProfile(_ profile: UserProfileState) -> Bool {
        let current = appViewModel.session.bootstrap.currentUsername?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return current?.localizedCaseInsensitiveCompare(profile.username) == .orderedSame
    }

    private func canMessage(_ profile: UserProfileState) -> Bool {
        !isOwnProfile(profile) && profile.canSendPrivateMessageToUser
    }

    private func humanize(_ raw: String?) -> String? {
        guard let raw, let date = FireChatTime.parse(raw) else { return nil }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}
