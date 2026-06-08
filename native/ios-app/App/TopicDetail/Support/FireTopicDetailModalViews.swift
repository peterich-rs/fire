import JXPhotoBrowser
import Photos
import SwiftUI
import UIKit

struct FireTopicVotersSheet: View {
    let voters: [VotedUserState]
    let isLoading: Bool

    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(.vertical, 20)
                    Spacer()
                }
            } else if voters.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.3")
                        .font(.title2)
                        .foregroundStyle(FireTheme.subtleInk)
                    Text("暂时还没有投票用户")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(FireTheme.ink)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                ForEach(voters, id: \.id) { voter in
                    HStack(spacing: 12) {
                        FireAvatarView(
                            avatarTemplate: voter.avatarTemplate,
                            username: voter.username,
                            size: 40
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text((voter.name ?? "").ifEmpty(voter.username))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(FireTheme.ink)
                            Text("@\(voter.username)")
                                .font(.caption)
                                .foregroundStyle(FireTheme.subtleInk)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("投票用户")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FirePostReactionPickerSheet: View {
    let post: TopicPostState
    let options: [FireReactionOption]
    let onSelectReaction: @MainActor (String) -> Void
    let onShowUsers: @MainActor (String) -> Void

    @State private var query = ""

    private var filteredOptions: [FireReactionOption] {
        FireTopicPresentation.filterReactionOptions(options, query: query)
    }

    var body: some View {
        List {
            ForEach(filteredOptions) { option in
                reactionRow(option)
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索表情")
        .navigationTitle("回应 #\(post.postNumber)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func reactionRow(_ option: FireReactionOption) -> some View {
        let count = post.reactions
            .first { $0.id.caseInsensitiveCompare(option.id) == .orderedSame }
            .map(\.count) ?? 0
        let isSelected = post.currentUserReaction?.id.caseInsensitiveCompare(option.id) == .orderedSame

        return HStack(spacing: 12) {
            Text(option.symbol)
                .font(.title3)
                .frame(width: 32, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text(option.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FireTheme.ink)
                Text("\(option.id) · \(count)")
                    .font(.caption)
                    .foregroundStyle(FireTheme.subtleInk)
            }

            Spacer()

            Button {
                onShowUsers(option.id)
            } label: {
                Image(systemName: "person.2")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("查看\(option.label)用户")

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FireTheme.accent)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectReaction(option.id)
        }
        .contextMenu {
            Button {
                onShowUsers(option.id)
            } label: {
                Label("查看回应用户", systemImage: "person.2")
            }
        }
    }
}

struct FireReactionUsersSheet: View {
    let groups: [ReactionUsersGroupState]
    let reactionID: String?

    var body: some View {
        List {
            if groups.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.2")
                        .font(.title2)
                        .foregroundStyle(FireTheme.subtleInk)
                    Text("暂时没有回应用户")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(FireTheme.ink)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                ForEach(groups, id: \.id) { group in
                    Section {
                        ForEach(group.users, id: \.id) { user in
                            HStack(spacing: 12) {
                                FireAvatarView(
                                    avatarTemplate: user.avatarTemplate,
                                    username: user.username,
                                    size: 36
                                )

                                VStack(alignment: .leading, spacing: 4) {
                                    Text((user.name ?? "").ifEmpty(user.username))
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(FireTheme.ink)
                                    Text("@\(user.username)")
                                        .font(.caption)
                                        .foregroundStyle(FireTheme.subtleInk)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    } header: {
                        let option = FireTopicPresentation.reactionOption(for: group.id)
                        Text("\(option.symbol) \(option.label) · \(group.count)")
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var title: String {
        guard let reactionID,
              !reactionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "回应用户"
        }
        let option = FireTopicPresentation.reactionOption(for: reactionID)
        return "\(option.symbol) \(option.label)"
    }
}

extension Array where Element == ReactionUsersGroupState {
    func filter(for reactionID: String?) -> [ReactionUsersGroupState] {
        guard let reactionID = reactionID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reactionID.isEmpty else {
            return self
        }
        return filter { group in
            group.id.caseInsensitiveCompare(reactionID) == .orderedSame
        }
    }
}

final class FireTopicPhotoBrowserController: JXPhotoBrowserViewController, JXPhotoBrowserDelegate {
    private enum PhotoSaveError: Error {
        case unknownFailure
    }

    private let image: FireCookedImage
    private let imageRequest: FireRemoteImageRequest
    private let toolbar = UIStackView()
    private let statusStack = UIStackView()
    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let retryButton = UIButton(type: .system)
    private weak var activeCell: JXZoomImageCell?
    private var loadedImage: UIImage?
    private var loadTask: Task<Void, Never>?

    init(image: FireCookedImage) {
        self.image = image
        self.imageRequest = FireTopicImageRequestBuilder.cookedImageRequest(image)
        super.init(nibName: nil, bundle: nil)
        delegate = self
        initialIndex = 0
        isLoopingEnabled = false
        transitionType = .fade
        itemSpacing = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureOverlayControls()
        showLoading()
    }

    func numberOfItems(in browser: JXPhotoBrowserViewController) -> Int {
        1
    }

    func photoBrowser(
        _ browser: JXPhotoBrowserViewController,
        cellForItemAt index: Int,
        at indexPath: IndexPath
    ) -> JXPhotoBrowserAnyCell {
        browser.dequeueReusableCell(
            withReuseIdentifier: JXZoomImageCell.reuseIdentifier,
            for: indexPath
        )
    }

    func photoBrowser(
        _ browser: JXPhotoBrowserViewController,
        willDisplay cell: JXPhotoBrowserAnyCell,
        at index: Int
    ) {
        guard let photoCell = cell as? JXZoomImageCell else { return }
        photoCell.imageView.contentMode = .scaleAspectFit
        photoCell.imageView.accessibilityLabel = image.altText?.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty("帖子图片")
        activeCell = photoCell
        if let loadedImage {
            photoCell.imageView.image = loadedImage
            photoCell.adjustImageViewFrame()
            hideStatus()
        } else {
            photoCell.imageView.image = nil
            loadImage()
        }
    }

    func photoBrowser(
        _ browser: JXPhotoBrowserViewController,
        didEndDisplaying cell: JXPhotoBrowserAnyCell,
        at index: Int
    ) {
        if activeCell === cell {
            activeCell = nil
        }
    }

    private func configureOverlayControls() {
        toolbar.axis = .horizontal
        toolbar.alignment = .center
        toolbar.distribution = .equalSpacing
        toolbar.spacing = 12
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)

        toolbar.addArrangedSubview(controlButton(systemName: "xmark", action: #selector(closeTapped)))
        toolbar.addArrangedSubview(UIView())
        toolbar.addArrangedSubview(controlButton(systemName: "square.and.arrow.up", action: #selector(shareTapped)))
        toolbar.addArrangedSubview(controlButton(systemName: "arrow.down.to.line", action: #selector(saveTapped)))

        statusStack.axis = .vertical
        statusStack.alignment = .center
        statusStack.spacing = 12
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusStack)

        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.textColor = .white
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        retryButton.setTitle("重试", for: .normal)
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        retryButton.tintColor = .white
        statusStack.addArrangedSubview(activityIndicator)
        statusStack.addArrangedSubview(statusLabel)
        statusStack.addArrangedSubview(retryButton)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            toolbar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            toolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            toolbar.heightAnchor.constraint(equalToConstant: 44),

            statusStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            statusStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])
    }

    private func controlButton(systemName: String, action: Selector) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: systemName)
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.42)
        configuration.cornerStyle = .capsule
        let button = UIButton(configuration: configuration)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.widthAnchor.constraint(equalToConstant: 42).isActive = true
        button.heightAnchor.constraint(equalToConstant: 42).isActive = true
        return button
    }

    private func loadImage() {
        loadTask?.cancel()
        showLoading()
        if let cachedImage = FireRemoteImagePipeline.shared.cachedImage(for: imageRequest) {
            applyLoadedImage(cachedImage)
            return
        }

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let resolvedImage = try await FireRemoteImagePipeline.shared.loadImage(for: imageRequest)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.applyLoadedImage(resolvedImage)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.showFailure()
                }
            }
        }
    }

    private func showLoading() {
        statusStack.isHidden = false
        retryButton.isHidden = true
        statusLabel.text = "图片加载中..."
        activityIndicator.startAnimating()
    }

    private func showFailure() {
        loadedImage = nil
        activeCell?.imageView.image = nil
        statusStack.isHidden = false
        retryButton.isHidden = false
        statusLabel.text = "图片加载失败"
        activityIndicator.stopAnimating()
    }

    private func hideStatus() {
        statusStack.isHidden = true
        activityIndicator.stopAnimating()
    }

    private func applyLoadedImage(_ image: UIImage) {
        loadedImage = image
        activeCell?.imageView.image = image
        activeCell?.adjustImageViewFrame()
        hideStatus()
    }

    @objc private func retryTapped() {
        loadImage()
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func shareTapped() {
        Task { @MainActor in
            guard let image = await resolvedToolbarImage() else { return }
            let controller = UIActivityViewController(activityItems: [image], applicationActivities: nil)
            present(controller, animated: true)
        }
    }

    @objc private func saveTapped() {
        Task { @MainActor in
            guard let image = await resolvedToolbarImage() else { return }
            let status = await photoLibraryAuthorizationStatus()
            guard status == .authorized || status == .limited else {
                presentAlert(title: "无法保存到相册", message: "Fire 需要照片权限才能保存当前图片。")
                return
            }
            do {
                try await saveImageToPhotoLibrary(image)
                presentAlert(title: "已保存到相册", message: "当前帖子图片已经保存。")
            } catch {
                presentAlert(title: "保存失败", message: "系统暂时无法写入相册，请稍后再试。")
            }
        }
    }

    @MainActor
    private func resolvedToolbarImage() async -> UIImage? {
        if let loadedImage {
            return loadedImage
        }
        do {
            let image = try await FireRemoteImagePipeline.shared.loadImage(for: imageRequest)
            applyLoadedImage(image)
            return image
        } catch {
            showFailure()
            return nil
        }
    }

    private func photoLibraryAuthorizationStatus() async -> PHAuthorizationStatus {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard currentStatus == .notDetermined else {
            return currentStatus
        }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func saveImageToPhotoLibrary(_ image: UIImage) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: PhotoSaveError.unknownFailure)
                }
            }
        }
    }

    private func presentAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .cancel))
        present(alert, animated: true)
    }
}

struct FirePostRepliesSheet: View {
    @Environment(\.dismiss) private var dismiss

    let post: TopicPostState
    let replies: [TopicPostState]
    let replyHistory: [TopicPostState]
    let isLoading: Bool
    let errorMessage: String?
    let baseURLString: String
    let onJumpToPost: (UInt32) -> Void
    let onRetry: () async -> Void

    private var hasContent: Bool {
        !replies.isEmpty || !replyHistory.isEmpty
    }

    var body: some View {
        List {
            if isLoading && !hasContent {
                loadingRow
            }

            if let errorMessage {
                errorRow(message: errorMessage)
            }

            if !replyHistory.isEmpty {
                Section("回复来源") {
                    ForEach(replyHistory, id: \.id) { reply in
                        FirePostReplyContextRow(
                            post: reply,
                            baseURLString: baseURLString,
                            onJump: onJumpToPost
                        )
                    }
                }
            }

            if !replies.isEmpty {
                Section("直接回复") {
                    ForEach(replies, id: \.id) { reply in
                        FirePostReplyContextRow(
                            post: reply,
                            baseURLString: baseURLString,
                            onJump: onJumpToPost
                        )
                    }
                }
            }

            if !isLoading && errorMessage == nil && !hasContent {
                emptyRow
            }
        }
        .navigationTitle("#\(post.postNumber) 的回复")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("收起") {
                    dismiss()
                }
            }
        }
    }

    private var loadingRow: some View {
        HStack {
            Spacer()
            ProgressView()
                .padding(.vertical, 20)
            Spacer()
        }
    }

    private func errorRow(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)

            Button {
                Task { await onRetry() }
            } label: {
                Label("重试", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 6)
    }

    private var emptyRow: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.title2)
                .foregroundStyle(FireTheme.subtleInk)
            Text("暂时没有可显示的回复上下文")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(FireTheme.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

private struct FirePostReplyContextRow: View {
    let post: TopicPostState
    let baseURLString: String
    let onJump: (UInt32) -> Void

    private var displayName: String {
        (post.name ?? "").ifEmpty(post.username.ifEmpty("Unknown"))
    }

    private var excerpt: String {
        (post.renderDocument?.plainText ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .ifEmpty("无正文预览")
    }

    var body: some View {
        Button {
            onJump(post.postNumber)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                FireAvatarView(
                    avatarTemplate: post.avatarTemplate,
                    username: post.username.ifEmpty("?"),
                    size: 34,
                    baseURLString: baseURLString
                )

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(displayName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(FireTheme.ink)
                            .lineLimit(1)

                        Text("#\(post.postNumber)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(FireTheme.tertiaryInk)

                        Spacer(minLength: 0)

                        Image(systemName: "arrow.up.forward")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(FireTheme.tertiaryInk)
                    }

                    Text(excerpt)
                        .font(.footnote)
                        .foregroundStyle(FireTheme.subtleInk)
                        .lineLimit(3)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

struct FireTopicImageViewer: View {
    let image: FireCookedImage

    private enum InteractionMode {
        case idle
        case zooming
        case panning
        case dismissing
    }

    private enum DragMode {
        case pan
        case dismiss
        case ignore
    }

    private enum ToolbarAction {
        case share
        case save
    }

    private enum PhotoSaveError: Error {
        case unknownFailure
    }

    @Environment(\.dismiss) private var dismiss
    @State private var interactionMode: InteractionMode = .idle
    @State private var activeDragMode: DragMode?
    @State private var activeToolbarAction: ToolbarAction?
    @State private var sharedImage: UIImage?
    @State private var isShowingShareSheet = false
    @State private var isShowingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var steadyZoomScale: CGFloat = 1
    @State private var gestureZoomScale: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var dragStartOffset: CGSize = .zero
    @State private var dismissOffset: CGSize = .zero

    private let minimumZoomScale: CGFloat = 1
    private let maximumZoomScale: CGFloat = 4
    private let dismissThreshold: CGFloat = 140
    private let dismissProgressDistance: CGFloat = 220
    private let imagePadding: CGFloat = 16

    private var imageRequest: FireRemoteImageRequest {
        FireRemoteImageRequest(url: image.url)
    }

    private var shareSubject: String {
        let fileName = image.url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return fileName.isEmpty ? "Fire 帖子图片" : fileName
    }

    private var effectiveZoomScale: CGFloat {
        clampedScale(steadyZoomScale * gestureZoomScale)
    }

    private var dismissProgress: CGFloat {
        min(max(dismissOffset.height / dismissProgressDistance, 0), 1)
    }

    private var backgroundOpacity: Double {
        Double(max(0.22, 1 - dismissProgress * 0.78))
    }

    private var contentScale: CGFloat {
        let dismissScale = max(0.88, 1 - dismissProgress * 0.12)
        return effectiveZoomScale * dismissScale
    }

    private var isToolbarBusy: Bool {
        activeToolbarAction != nil
    }

    var body: some View {
        GeometryReader { proxy in
            let containerSize = proxy.size

            ZStack {
                Color.black
                    .opacity(backgroundOpacity)
                    .ignoresSafeArea()

                FireRemoteImage(request: imageRequest) { loadedImage in
                    Image(uiImage: loadedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(imagePadding)
                } placeholder: { state in
                    switch state {
                    case .loading, .missingRequest:
                        ProgressView()
                            .tint(.white)
                    case .failure:
                        VStack(spacing: 12) {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                            Text("图片加载失败")
                                .font(.subheadline)
                        }
                        .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(contentScale)
                .offset(displayOffset(in: containerSize))
                .simultaneousGesture(magnificationGesture(in: containerSize))

                VStack {
                    HStack(spacing: 12) {
                        Spacer()

                        viewerControlButton(
                            systemName: "square.and.arrow.up",
                            isBusy: activeToolbarAction == .share,
                            action: { Task { await handleShareAction() } }
                        )
                        .disabled(isToolbarBusy)

                        viewerControlButton(
                            systemName: "arrow.down.to.line",
                            isBusy: activeToolbarAction == .save,
                            action: { Task { await handleSaveAction() } }
                        )
                        .disabled(isToolbarBusy)

                        viewerControlButton(systemName: "xmark", action: {
                            dismiss()
                        })
                    }
                    .padding(.top, proxy.safeAreaInsets.top + 12)
                    .padding(.horizontal, 16)

                    Spacer()
                }
                .opacity(max(0.4, backgroundOpacity))
            }
            .contentShape(Rectangle())
            .simultaneousGesture(dragGesture(in: containerSize))
        }
        .sheet(isPresented: $isShowingShareSheet, onDismiss: {
            sharedImage = nil
        }) {
            Group {
                if let sharedImage {
                    FireActivityShareSheet(
                        activityItems: [sharedImage],
                        subject: shareSubject
                    )
                }
            }
            .fireSheet(presented: $isShowingShareSheet)
        }
        .alert(alertTitle, isPresented: $isShowingAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private func viewerControlButton(
        systemName: String,
        isBusy: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
            .frame(width: 42, height: 42)
            .background(
                Circle()
                    .fill(Color.black.opacity(0.34))
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func handleShareAction() async {
        guard activeToolbarAction == nil else { return }

        activeToolbarAction = .share
        defer { activeToolbarAction = nil }

        do {
            let resolvedImage = try await FireRemoteImagePipeline.shared.loadImage(for: imageRequest)
            sharedImage = resolvedImage
            isShowingShareSheet = true
        } catch {
            presentAlert(
                title: "无法分享图片",
                message: "图片还没加载完成或下载失败，请稍后再试。"
            )
        }
    }

    @MainActor
    private func handleSaveAction() async {
        guard activeToolbarAction == nil else { return }

        activeToolbarAction = .save
        defer { activeToolbarAction = nil }

        let resolvedImage: UIImage
        do {
            resolvedImage = try await FireRemoteImagePipeline.shared.loadImage(for: imageRequest)
        } catch {
            presentAlert(
                title: "无法保存图片",
                message: "图片还没加载完成或下载失败，请稍后再试。"
            )
            return
        }

        let authorizationStatus = await photoLibraryAuthorizationStatus()
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            presentAlert(
                title: "无法保存到相册",
                message: "Fire 需要照片权限才能把当前图片保存到相册，请在系统设置里允许添加照片。"
            )
            return
        }

        do {
            try await saveImageToPhotoLibrary(resolvedImage)
            presentAlert(
                title: "已保存到相册",
                message: "当前帖子图片已经保存到系统相册。"
            )
        } catch {
            presentAlert(
                title: "保存失败",
                message: "系统暂时无法写入相册，请稍后再试。"
            )
        }
    }

    @MainActor
    private func presentAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        isShowingAlert = true
    }

    private func photoLibraryAuthorizationStatus() async -> PHAuthorizationStatus {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard currentStatus == .notDetermined else {
            return currentStatus
        }

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func saveImageToPhotoLibrary(_ image: UIImage) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: PhotoSaveError.unknownFailure)
                }
            }
        }
    }

    private func magnificationGesture(in containerSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                activeDragMode = nil
                dismissOffset = .zero
                interactionMode = .zooming
                gestureZoomScale = value
            }
            .onEnded { value in
                let resolvedScale = clampedScale(steadyZoomScale * value)
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    steadyZoomScale = resolvedScale
                    gestureZoomScale = 1
                    if resolvedScale <= minimumZoomScale + 0.01 {
                        resetTransformState()
                    } else {
                        panOffset = clampedPanOffset(panOffset, in: containerSize, scale: resolvedScale)
                        interactionMode = .panning
                    }
                }
            }
    }

    private func dragGesture(in containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                handleDragChanged(value, in: containerSize)
            }
            .onEnded { value in
                handleDragEnded(value, in: containerSize)
            }
    }

    private func handleDragChanged(_ value: DragGesture.Value, in containerSize: CGSize) {
        guard interactionMode != .zooming else { return }

        if activeDragMode == nil {
            if effectiveZoomScale > minimumZoomScale + 0.01 {
                activeDragMode = .pan
                dragStartOffset = panOffset
            } else if value.translation.height > 0,
                      abs(value.translation.height) > abs(value.translation.width) {
                activeDragMode = .dismiss
            } else {
                activeDragMode = .ignore
            }
        }

        switch activeDragMode {
        case .pan:
            interactionMode = .panning
            dismissOffset = .zero
            let proposedOffset = CGSize(
                width: dragStartOffset.width + value.translation.width,
                height: dragStartOffset.height + value.translation.height
            )
            panOffset = clampedPanOffset(proposedOffset, in: containerSize, scale: effectiveZoomScale)
        case .dismiss:
            interactionMode = .dismissing
            let horizontalDrift = value.translation.width * 0.18
            let verticalOffset = value.translation.height > dismissThreshold
                ? dismissThreshold + (value.translation.height - dismissThreshold) * 0.72
                : value.translation.height
            dismissOffset = CGSize(width: horizontalDrift, height: verticalOffset)
        case .ignore, .none:
            break
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value, in containerSize: CGSize) {
        defer { activeDragMode = nil }

        switch activeDragMode {
        case .pan:
            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                panOffset = clampedPanOffset(panOffset, in: containerSize, scale: effectiveZoomScale)
            }
            interactionMode = effectiveZoomScale > minimumZoomScale + 0.01 ? .panning : .idle
        case .dismiss:
            let projectedDismissDistance = max(value.translation.height, value.predictedEndTranslation.height)
            if projectedDismissDistance > dismissThreshold {
                dismiss()
            } else {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    dismissOffset = .zero
                    interactionMode = effectiveZoomScale > minimumZoomScale + 0.01 ? .panning : .idle
                }
            }
        case .ignore, .none:
            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                dismissOffset = .zero
            }
            interactionMode = effectiveZoomScale > minimumZoomScale + 0.01 ? .panning : .idle
        }
    }

    private func displayOffset(in containerSize: CGSize) -> CGSize {
        let clampedPan = clampedPanOffset(panOffset, in: containerSize, scale: effectiveZoomScale)
        return CGSize(
            width: clampedPan.width + dismissOffset.width,
            height: clampedPan.height + dismissOffset.height
        )
    }

    private func resetTransformState() {
        steadyZoomScale = minimumZoomScale
        gestureZoomScale = 1
        panOffset = .zero
        dragStartOffset = .zero
        dismissOffset = .zero
        interactionMode = .idle
    }

    private func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, minimumZoomScale), maximumZoomScale)
    }

    private func clampedPanOffset(_ proposedOffset: CGSize, in containerSize: CGSize, scale: CGFloat) -> CGSize {
        let maxOffset = maximumPanOffset(in: containerSize, scale: scale)
        return CGSize(
            width: min(max(proposedOffset.width, -maxOffset.width), maxOffset.width),
            height: min(max(proposedOffset.height, -maxOffset.height), maxOffset.height)
        )
    }

    private func maximumPanOffset(in containerSize: CGSize, scale: CGFloat) -> CGSize {
        guard scale > minimumZoomScale else {
            return .zero
        }

        let fittedSize = fittedImageSize(in: containerSize)
        let scaledSize = CGSize(width: fittedSize.width * scale, height: fittedSize.height * scale)
        return CGSize(
            width: max((scaledSize.width - fittedSize.width) / 2, 0),
            height: max((scaledSize.height - fittedSize.height) / 2, 0)
        )
    }

    private func fittedImageSize(in containerSize: CGSize) -> CGSize {
        let availableWidth = max(containerSize.width - imagePadding * 2, 1)
        let availableHeight = max(containerSize.height - imagePadding * 2, 1)

        guard let aspectRatio = image.aspectRatio, aspectRatio > 0 else {
            return CGSize(width: availableWidth, height: availableHeight)
        }

        let containerAspectRatio = availableWidth / availableHeight
        if aspectRatio > containerAspectRatio {
            return CGSize(width: availableWidth, height: availableWidth / aspectRatio)
        }
        return CGSize(width: availableHeight * aspectRatio, height: availableHeight)
    }
}
