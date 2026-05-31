import AsyncDisplayKit
import UIKit

final class FirePostCollectionViewCell: UICollectionViewCell, UIGestureRecognizerDelegate {
    static let reuseID = "FirePostCollectionViewCell"

    private static let replyContextActionID = UIAction.Identifier(
        "FirePostCollectionViewCell.replyContext"
    )
    private static let textExpansionActionID = UIAction.Identifier(
        "FirePostCollectionViewCell.textExpansion"
    )
    private static let replyShortcutActionID = UIAction.Identifier(
        "FirePostCollectionViewCell.replyShortcut"
    )
    private static let replySwipeTriggerThreshold: CGFloat = 55
    private static let replySwipeMaxOffset: CGFloat = 75
    private static let replyIndicatorSize = CGSize(width: 32, height: 32)
    private static let monogramCache = NSCache<NSString, NSString>()
    private static let accentTextColor = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.96, green: 0.45, blue: 0.22, alpha: 1)
        }
        return UIColor(red: 0.91, green: 0.39, blue: 0.18, alpha: 1)
    }
    private static let tertiaryInkColor = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.62, green: 0.63, blue: 0.67, alpha: 1)
        }
        return UIColor(red: 0.52, green: 0.52, blue: 0.55, alpha: 1)
    }

    // MARK: - Subviews

    private let avatarImageView = UIImageView()
    private let avatarMonogramView = UILabel()
    private let avatarContainerView = UIView()
    private let threadLineView = UIView()
    private let usernameLabel = UILabel()
    private let replyContextButton = UIButton(type: .custom)
    private let timestampLabel = UILabel()
    private let acceptedAnswerLabel = UILabel()
    private let postNumberLabel = UILabel()
    private let menuButton = UIButton(type: .system)
    private let metaStack = UIStackView()
    private let richTextContainer = FirePostRichTextContainerView()
    private let textExpansionButton = UIButton(type: .system)
    private let imageContainerView = UIView()
    private let pollContainerView = UIView()
    private let replyShortcutButton = UIButton(type: .system)
    private let reactionScrollView = UIScrollView()
    private let reactionStack = UIStackView()
    private let dividerView = UIView()
    private let replyIndicatorView = UIImageView(image: UIImage(systemName: "arrowshape.turn.up.left.fill"))

    // MARK: - State

    private var currentLayout: FirePostCellLayout?
    private var currentPayload: FirePostCellRenderPayload?
    private var currentCallbacks: FirePostCellCallbacks?
    private var imageNodes: [ASImageNode] = []
    private var imageTasks: [String: Task<Void, Never>] = [:]
    private var pollViews: [FirePostPollView] = []
    private var avatarTask: Task<Void, Never>?
    private var emojiLoadTasks: [String: Task<Void, Never>] = [:]
    private var avatarRequestKey: String?
    private var imageSignature: [String] = []
    private var pollSignature: [String] = []
    private var reactionSignature: String?
    private var swipeOffset: CGFloat = 0
    private var replyTriggered = false
    private lazy var swipeGestureRecognizer: UIPanGestureRecognizer = {
        let gestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handleSwipePan(_:)))
        gestureRecognizer.delegate = self
        gestureRecognizer.cancelsTouchesInView = false
        return gestureRecognizer
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupSubviews() {
        clipsToBounds = true
        contentView.backgroundColor = .systemBackground
        backgroundView = UIView(frame: .zero)
        backgroundView?.backgroundColor = .clear
        replyIndicatorView.contentMode = .center
        replyIndicatorView.alpha = 0
        backgroundView?.addSubview(replyIndicatorView)
        contentView.addGestureRecognizer(swipeGestureRecognizer)

        // Avatar
        avatarContainerView.addSubview(avatarImageView)
        avatarContainerView.addSubview(avatarMonogramView)
        avatarContainerView.isHidden = true
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarMonogramView.textAlignment = .center
        avatarMonogramView.textColor = .white
        avatarMonogramView.adjustsFontForContentSizeCategory = true

        // Thread line
        threadLineView.backgroundColor = .separator
        threadLineView.isHidden = true

        // Meta line
        usernameLabel.textColor = .label
        usernameLabel.adjustsFontForContentSizeCategory = true
        usernameLabel.numberOfLines = 1
        usernameLabel.lineBreakMode = .byTruncatingTail
        usernameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        usernameLabel.setContentHuggingPriority(.required, for: .horizontal)

        replyContextButton.isHidden = true
        replyContextButton.titleLabel?.adjustsFontForContentSizeCategory = true
        replyContextButton.titleLabel?.numberOfLines = 1
        replyContextButton.titleLabel?.lineBreakMode = .byTruncatingTail
        replyContextButton.contentHorizontalAlignment = .leading
        replyContextButton.contentVerticalAlignment = .center
        replyContextButton.backgroundColor = .clear
        replyContextButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        replyContextButton.setContentHuggingPriority(.required, for: .horizontal)

        timestampLabel.textColor = .tertiaryLabel
        timestampLabel.adjustsFontForContentSizeCategory = true
        timestampLabel.setContentHuggingPriority(.required, for: .horizontal)

        acceptedAnswerLabel.textColor = .systemGreen
        acceptedAnswerLabel.adjustsFontForContentSizeCategory = true
        acceptedAnswerLabel.isHidden = true
        acceptedAnswerLabel.setContentHuggingPriority(.required, for: .horizontal)

        postNumberLabel.textColor = .tertiaryLabel
        postNumberLabel.adjustsFontForContentSizeCategory = true
        postNumberLabel.setContentHuggingPriority(.required, for: .horizontal)

        menuButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        menuButton.tintColor = .tertiaryLabel
        menuButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .caption1)
        menuButton.titleLabel?.adjustsFontForContentSizeCategory = true
        menuButton.isHidden = true
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.setContentHuggingPriority(.required, for: .horizontal)
        menuButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        menuButton.accessibilityLabel = "帖子操作"

        metaStack.axis = .horizontal
        metaStack.alignment = .center
        metaStack.spacing = 6
        metaStack.addArrangedSubview(usernameLabel)
        metaStack.addArrangedSubview(replyContextButton)
        metaStack.addArrangedSubview(timestampLabel)
        metaStack.addArrangedSubview(UIView())
        metaStack.addArrangedSubview(acceptedAnswerLabel)
        metaStack.addArrangedSubview(postNumberLabel)
        metaStack.addArrangedSubview(menuButton)

        // Rich text
        richTextContainer.isHidden = true

        textExpansionButton.isHidden = true
        textExpansionButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .caption1)
        textExpansionButton.titleLabel?.adjustsFontForContentSizeCategory = true
        textExpansionButton.titleLabel?.lineBreakMode = .byTruncatingTail
        textExpansionButton.contentHorizontalAlignment = .leading
        textExpansionButton.setTitle("展开", for: .normal)
        textExpansionButton.setContentHuggingPriority(.required, for: .horizontal)
        textExpansionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        textExpansionButton.accessibilityLabel = "展开全文"

        // Images
        imageContainerView.isHidden = true

        // Polls
        pollContainerView.isHidden = true

        replyShortcutButton.isHidden = true
        replyShortcutButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .caption1)
        replyShortcutButton.titleLabel?.adjustsFontForContentSizeCategory = true
        replyShortcutButton.titleLabel?.lineBreakMode = .byTruncatingTail
        replyShortcutButton.contentHorizontalAlignment = .leading
        replyShortcutButton.backgroundColor = .clear
        replyShortcutButton.setContentHuggingPriority(.required, for: .horizontal)
        replyShortcutButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        replyShortcutButton.accessibilityLabel = "查看更多回复"

        // Reactions
        reactionScrollView.showsHorizontalScrollIndicator = false
        reactionScrollView.isHidden = true
        reactionStack.axis = .horizontal
        reactionStack.spacing = 8
        reactionStack.translatesAutoresizingMaskIntoConstraints = false
        reactionScrollView.addSubview(reactionStack)
        NSLayoutConstraint.activate([
            reactionStack.leadingAnchor.constraint(equalTo: reactionScrollView.contentLayoutGuide.leadingAnchor),
            reactionStack.trailingAnchor.constraint(equalTo: reactionScrollView.contentLayoutGuide.trailingAnchor),
            reactionStack.topAnchor.constraint(equalTo: reactionScrollView.contentLayoutGuide.topAnchor),
            reactionStack.bottomAnchor.constraint(equalTo: reactionScrollView.contentLayoutGuide.bottomAnchor),
            reactionStack.heightAnchor.constraint(equalTo: reactionScrollView.frameLayoutGuide.heightAnchor),
        ])

        // Divider
        dividerView.backgroundColor = .separator
        dividerView.isHidden = true

        contentView.addSubview(avatarContainerView)
        contentView.addSubview(threadLineView)
        contentView.addSubview(metaStack)
        contentView.addSubview(richTextContainer)
        contentView.addSubview(textExpansionButton)
        contentView.addSubview(imageContainerView)
        contentView.addSubview(pollContainerView)
        contentView.addSubview(replyShortcutButton)
        contentView.addSubview(reactionScrollView)
        contentView.addSubview(dividerView)

        applyTypography()
        applyColors()
    }

    private func applyTypography() {
        let subheadlinePointSize = UIFont.preferredFont(forTextStyle: .subheadline).pointSize
        usernameLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: UIFont.systemFont(ofSize: subheadlinePointSize, weight: .semibold)
        )

        replyContextButton.titleLabel?.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: UIFont.systemFont(ofSize: subheadlinePointSize, weight: .semibold)
        )

        let captionPointSize = UIFont.preferredFont(forTextStyle: .caption2).pointSize
        timestampLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
        acceptedAnswerLabel.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(
            for: UIFont.systemFont(ofSize: captionPointSize, weight: .medium)
        )
        postNumberLabel.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(
            for: UIFont.monospacedDigitSystemFont(ofSize: captionPointSize, weight: .regular)
        )
        menuButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .caption1)
        textExpansionButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .caption1)
        replyShortcutButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .caption1)
    }

    private func applyColors() {
        contentView.backgroundColor = .systemBackground
        threadLineView.backgroundColor = .separator
        dividerView.backgroundColor = .separator
        replyContextButton.setTitleColor(Self.accentTextColor, for: .normal)
        replyContextButton.tintColor = Self.accentTextColor
        timestampLabel.textColor = Self.tertiaryInkColor
        postNumberLabel.textColor = Self.tertiaryInkColor
        menuButton.tintColor = Self.tertiaryInkColor
        textExpansionButton.setTitleColor(Self.accentTextColor, for: .normal)
        textExpansionButton.tintColor = Self.accentTextColor
        replyShortcutButton.setTitleColor(Self.accentTextColor, for: .normal)
        replyShortcutButton.tintColor = Self.accentTextColor
        replyIndicatorView.tintColor = replyTriggered ? Self.accentTextColor : .tertiaryLabel
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backgroundView?.frame = bounds
        replyIndicatorView.frame = CGRect(
            x: 4,
            y: max((bounds.height - Self.replyIndicatorSize.height) / 2, 0),
            width: Self.replyIndicatorSize.width,
            height: Self.replyIndicatorSize.height
        )
    }

    // MARK: - Bind

    func bind(layout: FirePostCellLayout, payload: FirePostCellRenderPayload, callbacks: FirePostCellCallbacks) {
        currentLayout = layout
        currentPayload = payload
        currentCallbacks = callbacks
        resetSwipeState(animated: false)

        let post = payload.post
        let vd = FirePostCellLayoutCalculator.visualDepth(for: layout.key.depth)
        let avatarSz = vd > 0 ? FirePostCellLayoutCalculator.avatarSizeNested : FirePostCellLayoutCalculator.avatarSizeRoot

        // Avatar
        avatarContainerView.frame = layout.avatarFrame
        avatarContainerView.isHidden = false
        avatarContainerView.layer.cornerRadius = avatarSz / 2
        avatarContainerView.clipsToBounds = true

        avatarImageView.frame = avatarContainerView.bounds
        avatarMonogramView.frame = avatarContainerView.bounds
        avatarMonogramView.font = .systemFont(ofSize: avatarSz * 0.36, weight: .bold)

        loadAvatar(avatarTemplate: post.avatarTemplate, username: post.username, size: avatarSz, baseURLString: payload.baseURLString)

        // Thread line
        if let threadLineFrame = layout.threadLineFrame {
            threadLineView.frame = threadLineFrame
            threadLineView.isHidden = false
        } else {
            threadLineView.isHidden = true
        }

        // Meta
        metaStack.frame = layout.metaFrame
        usernameLabel.text = post.username.isEmpty ? "Unknown" : post.username
        usernameLabel.accessibilityLabel = usernameLabel.text
        replyContextButton.removeAction(identifiedBy: Self.replyContextActionID, for: .touchUpInside)

        if let replyContext = payload.replyContext,
           let targetPN = payload.replyTargetPostNumber, targetPN > 0 {
            replyContextButton.setTitle(replyContext, for: .normal)
            replyContextButton.isHidden = false
            replyContextButton.accessibilityLabel = replyContext
            replyContextButton.addAction(UIAction(identifier: Self.replyContextActionID) { [weak self] _ in
                guard let self, let callbacks = self.currentCallbacks else { return }
                callbacks.onOpenReplyTarget(targetPN)
            }, for: .touchUpInside)
        } else {
            replyContextButton.setTitle(nil, for: .normal)
            replyContextButton.isHidden = true
            replyContextButton.accessibilityLabel = nil
        }

        timestampLabel.text = FireTopicPresentation.compactTimestamp(post.createdAt)
        timestampLabel.accessibilityLabel = timestampLabel.text
        acceptedAnswerLabel.isHidden = !post.acceptedAnswer
        acceptedAnswerLabel.text = nil
        acceptedAnswerLabel.attributedText = nil
        if post.acceptedAnswer {
            acceptedAnswerLabel.attributedText = acceptedAnswerAttributedText()
            acceptedAnswerLabel.accessibilityLabel = "已采纳"
        } else {
            acceptedAnswerLabel.accessibilityLabel = nil
        }
        postNumberLabel.text = "#\(post.postNumber)"
        postNumberLabel.accessibilityLabel = "楼层 #\(post.postNumber)"

        // Menu
        let canShowMenu = post.canEdit
            || (payload.canWriteInteractions && !post.hidden)
            || post.canRecover
            || (post.canDelete && !post.hidden)
        menuButton.isHidden = !canShowMenu
        if canShowMenu {
            menuButton.menu = buildMenu(for: post, callbacks: callbacks, canWrite: payload.canWriteInteractions, isMutating: payload.isMutating)
        } else {
            menuButton.menu = nil
        }

        // Rich text
        if let textFrame = layout.textFrame, let attrText = payload.renderContent.attributedText, attrText.length > 0 {
            richTextContainer.isHidden = false
            richTextContainer.frame = textFrame
            let contentID = "post:\(post.id)|render:\(payload.renderContent.signature.token)"
            richTextContainer.configure(
                attributedText: attrText,
                contentID: contentID,
                containerSize: layout.textContainerSize,
                maximumNumberOfLines: layout.textExpansionFrame == nil
                    ? 0
                    : UInt(FirePostTextExpansionState.collapsedLineLimit)
            )
            richTextContainer.onLinkTapped = { [weak self] url in
                guard let self, let callbacks = self.currentCallbacks else { return }
                callbacks.onLinkTapped(url)
            }
            richTextContainer.accessibilityLabel = payload.renderContent.plainText
        } else {
            richTextContainer.isHidden = true
            richTextContainer.resetContent()
            richTextContainer.accessibilityLabel = nil
        }

        textExpansionButton.removeAction(identifiedBy: Self.textExpansionActionID, for: .touchUpInside)
        if let textExpansionFrame = layout.textExpansionFrame {
            textExpansionButton.frame = textExpansionFrame
            textExpansionButton.isHidden = false
            textExpansionButton.setTitle("展开", for: .normal)
            textExpansionButton.addAction(UIAction(identifier: Self.textExpansionActionID) { [weak self] _ in
                guard let self,
                      let payload = self.currentPayload,
                      let callbacks = self.currentCallbacks else {
                    return
                }
                callbacks.onExpandText(payload.post)
            }, for: .touchUpInside)
        } else {
            textExpansionButton.isHidden = true
            textExpansionButton.frame = .zero
        }

        // Images
        let images = payload.renderContent.imageAttachments
        if images.isEmpty || layout.imageFrames.isEmpty {
            imageContainerView.isHidden = true
            imageContainerView.frame = .zero
            clearImageViews()
        } else {
            let imageContainerFrame = unionFrame(for: layout.imageFrames)
            imageContainerView.isHidden = false
            imageContainerView.frame = imageContainerFrame
            configureImageViews(images: images, frames: layout.imageFrames, containerFrame: imageContainerFrame)
        }

        // Polls
        let pollModels = FirePostPollRenderModel.models(from: post.polls)
        if pollModels.isEmpty || layout.pollFrames.isEmpty {
            pollContainerView.isHidden = true
            pollContainerView.frame = .zero
            clearPollViews()
        } else {
            let displayedPolls = Array(post.polls.prefix(layout.pollFrames.count))
            let displayedModels = Array(pollModels.prefix(layout.pollFrames.count))
            let pollContainerFrame = unionFrame(for: layout.pollFrames)
            pollContainerView.isHidden = false
            pollContainerView.frame = pollContainerFrame
            configurePollViews(
                polls: displayedPolls,
                models: displayedModels,
                frames: layout.pollFrames,
                containerFrame: pollContainerFrame,
                canInteract: payload.canWriteInteractions,
                isMutating: payload.isMutating
            )
        }

        replyShortcutButton.removeAction(identifiedBy: Self.replyShortcutActionID, for: .touchUpInside)
        if let replyShortcutFrame = layout.replyShortcutFrame,
           let replyShortcutCount = payload.replyShortcutCount {
            replyShortcutButton.frame = replyShortcutFrame
            replyShortcutButton.isHidden = false
            let title = replyShortcutCount > 0
                ? "查看更多 \(replyShortcutCount) 条回复"
                : "查看更多回复"
            replyShortcutButton.setTitle(title, for: .normal)
            replyShortcutButton.accessibilityLabel = title
            replyShortcutButton.addAction(UIAction(identifier: Self.replyShortcutActionID) { [weak self] _ in
                guard let self,
                      let payload = self.currentPayload,
                      let callbacks = self.currentCallbacks else {
                    return
                }
                callbacks.onOpenReplies(payload.post)
            }, for: .touchUpInside)
        } else {
            replyShortcutButton.isHidden = true
            replyShortcutButton.frame = .zero
            replyShortcutButton.setTitle(nil, for: .normal)
        }

        // Reactions
        if let reactionsFrame = layout.reactionsFrame, !post.reactions.isEmpty {
            reactionScrollView.isHidden = false
            reactionScrollView.frame = reactionsFrame
            let nextReactionSignature = Self.reactionSignature(
                post: post,
                canWrite: payload.canWriteInteractions,
                isMutating: payload.isMutating
            )
            if reactionSignature != nextReactionSignature {
                reactionScrollView.contentOffset = .zero
                rebuildReactionCapsules(post: post, canWrite: payload.canWriteInteractions, isMutating: payload.isMutating)
                reactionSignature = nextReactionSignature
            }
        } else {
            reactionScrollView.isHidden = true
            clearReactionCapsules()
            reactionSignature = nil
        }

        // Divider
        if let dividerFrame = layout.dividerFrame, payload.showsDivider {
            dividerView.frame = dividerFrame
            dividerView.isHidden = false
        } else {
            dividerView.isHidden = true
        }
    }

    // MARK: - Reuse

    override func prepareForReuse() {
        super.prepareForReuse()

        currentLayout = nil
        currentPayload = nil
        currentCallbacks = nil
        resetSwipeState(animated: false)

        avatarTask?.cancel()
        avatarTask = nil
        avatarRequestKey = nil
        avatarImageView.image = nil
        avatarMonogramView.text = nil
        avatarContainerView.isHidden = true
        avatarContainerView.frame = .zero
        threadLineView.isHidden = true
        threadLineView.frame = .zero

        usernameLabel.text = nil
        usernameLabel.accessibilityLabel = nil
        replyContextButton.removeAction(identifiedBy: Self.replyContextActionID, for: .touchUpInside)
        replyContextButton.setTitle(nil, for: .normal)
        replyContextButton.isHidden = true
        replyContextButton.accessibilityLabel = nil
        timestampLabel.text = nil
        timestampLabel.accessibilityLabel = nil
        acceptedAnswerLabel.isHidden = true
        acceptedAnswerLabel.text = nil
        acceptedAnswerLabel.attributedText = nil
        acceptedAnswerLabel.accessibilityLabel = nil
        postNumberLabel.text = nil
        postNumberLabel.accessibilityLabel = nil
        menuButton.isHidden = true
        menuButton.menu = nil

        richTextContainer.isHidden = true
        richTextContainer.resetContent()
        richTextContainer.onLinkTapped = nil
        richTextContainer.accessibilityLabel = nil
        textExpansionButton.removeAction(identifiedBy: Self.textExpansionActionID, for: .touchUpInside)
        textExpansionButton.isHidden = true
        textExpansionButton.frame = .zero

        clearImageViews()
        clearPollViews()
        emojiLoadTasks.values.forEach { $0.cancel() }
        emojiLoadTasks.removeAll()
        imageContainerView.isHidden = true
        imageContainerView.frame = .zero
        pollContainerView.isHidden = true
        pollContainerView.frame = .zero
        replyShortcutButton.removeAction(identifiedBy: Self.replyShortcutActionID, for: .touchUpInside)
        replyShortcutButton.isHidden = true
        replyShortcutButton.frame = .zero
        replyShortcutButton.setTitle(nil, for: .normal)

        reactionScrollView.isHidden = true
        reactionScrollView.contentOffset = .zero
        clearReactionCapsules()
        reactionSignature = nil

        dividerView.isHidden = true
        dividerView.frame = .zero
        applyColors()
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        if let layout = currentLayout {
            layoutAttributes.frame.size.height = layout.totalHeight
        }
        return layoutAttributes
    }

    // MARK: - Avatar Loading

    private func loadAvatar(avatarTemplate: String?, username: String, size: CGFloat, baseURLString: String) {
        let resolvedUsername = username.isEmpty ? "?" : username
        let monogram = Self.cachedMonogram(for: resolvedUsername)
        let avatarURL = fireAvatarURL(
            avatarTemplate: avatarTemplate,
            size: size,
            scale: UIScreen.main.scale,
            baseURLString: baseURLString
        )
        let nextRequestKey = avatarURL?.absoluteString ?? "fallback:\(resolvedUsername):\(Int(size.rounded()))"
        if avatarRequestKey == nextRequestKey {
            return
        }

        avatarRequestKey = nextRequestKey
        avatarTask?.cancel()
        avatarTask = nil

        avatarMonogramView.text = monogram
        avatarMonogramView.isHidden = false
        avatarImageView.isHidden = true
        avatarContainerView.backgroundColor = .systemBlue

        guard let avatarURL else {
            return
        }

        let request = FireRemoteImageRequest(url: avatarURL)

        if let cached = FireRemoteImagePipeline.shared.cachedImage(for: request) {
            applyAvatarImage(cached)
            return
        }

        avatarTask = Task { [weak self] in
            do {
                let image = try await FireRemoteImagePipeline.shared.loadImage(for: request)
                guard !Task.isCancelled else { return }
                _ = await MainActor.run {
                    guard self?.avatarRequestKey == nextRequestKey else { return }
                    self?.applyAvatarImage(image)
                }
            } catch {
                // Keep monogram fallback
            }
        }
    }

    private static func cachedMonogram(for username: String) -> String {
        let key = username as NSString
        if let cached = monogramCache.object(forKey: key) {
            return cached as String
        }

        let monogram = monogramForUsername(username: username)
        monogramCache.setObject(monogram as NSString, forKey: key)
        return monogram
    }

    private func applyAvatarImage(_ image: UIImage) {
        avatarImageView.image = image
        avatarImageView.isHidden = false
        avatarMonogramView.isHidden = true
    }

    // MARK: - Image Loading

    private func configureImageViews(
        images: [FireCookedImage],
        frames: [CGRect],
        containerFrame: CGRect
    ) {
        let displayedImages = Array(images.prefix(frames.count))
        let nextSignature = displayedImages.map(\.id)
        guard imageSignature == nextSignature,
              imageNodes.count == displayedImages.count else {
            rebuildImageViews(images: displayedImages, frames: frames, containerFrame: containerFrame)
            return
        }

        applyImageNodeFrames(images: displayedImages, frames: frames, containerFrame: containerFrame)
    }

    private func rebuildImageViews(
        images: [FireCookedImage],
        frames: [CGRect],
        containerFrame: CGRect
    ) {
        clearImageViews()
        imageSignature = images.map(\.id)

        for (index, image) in images.enumerated() {
            guard index < frames.count else { break }
            let imageNode = ASImageNode()
            imageNode.contentMode = .scaleAspectFit
            imageNode.clipsToBounds = true
            imageNode.cornerRadius = 16
            imageNode.borderColor = UIColor.separator.cgColor
            imageNode.borderWidth = 0.5
            imageNode.placeholderEnabled = true
            imageNode.placeholderColor = .tertiarySystemFill
            imageNode.frame = Self.relativeImageFrame(
                frame: frames[index],
                containerFrame: containerFrame
            )
            imageNode.backgroundColor = .tertiarySystemFill
            imageNode.isUserInteractionEnabled = true
            imageNode.view.tag = index
            imageNode.view.isAccessibilityElement = true
            imageNode.view.accessibilityTraits = [.image, .button]
            let altText = image.altText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            imageNode.view.accessibilityLabel = altText.isEmpty ? "帖子图片" : altText

            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleImageTap(_:)))
            imageNode.view.addGestureRecognizer(tapGesture)

            imageContainerView.addSubview(imageNode.view)
            imageNodes.append(imageNode)

            loadImage(into: imageNode, url: image.url, cacheKey: image.id)
        }
    }

    private func applyImageNodeFrames(
        images: [FireCookedImage],
        frames: [CGRect],
        containerFrame: CGRect
    ) {
        for (index, imageNode) in imageNodes.enumerated() {
            guard index < frames.count, index < images.count else { break }
            imageNode.frame = Self.relativeImageFrame(
                frame: frames[index],
                containerFrame: containerFrame
            )
            imageNode.view.tag = index
            let altText = images[index].altText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            imageNode.view.accessibilityLabel = altText.isEmpty ? "帖子图片" : altText
        }
    }

    private static func relativeImageFrame(frame: CGRect, containerFrame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX - containerFrame.minX,
            y: frame.minY - containerFrame.minY,
            width: frame.width,
            height: frame.height
        )
    }

    private func loadImage(into imageNode: ASImageNode, url: URL, cacheKey: String) {
        let request = FireRemoteImageRequest(url: url)
        if let cached = FireRemoteImagePipeline.shared.cachedImage(for: request) {
            imageNode.image = cached
            imageNode.backgroundColor = .clear
            return
        }

        imageTasks[cacheKey] = Task { [weak self] in
            do {
                let image = try await FireRemoteImagePipeline.shared.loadImage(for: request)
                guard !Task.isCancelled else { return }
                _ = await MainActor.run {
                    imageNode.image = image
                    imageNode.backgroundColor = .clear
                    self?.imageTasks.removeValue(forKey: cacheKey)
                }
            } catch {
                _ = await MainActor.run {
                    self?.imageTasks.removeValue(forKey: cacheKey)
                }
            }
        }
    }

    private func cancelImageTasks() {
        imageTasks.values.forEach { $0.cancel() }
        imageTasks.removeAll()
    }

    private func clearImageViews() {
        cancelImageTasks()
        imageNodes.forEach { $0.view.removeFromSuperview() }
        imageNodes = []
        imageSignature = []
    }

    // MARK: - Polls

    private func configurePollViews(
        polls: [PollState],
        models: [FirePostPollRenderModel],
        frames: [CGRect],
        containerFrame: CGRect,
        canInteract: Bool,
        isMutating: Bool
    ) {
        let displayedModels = Array(models.prefix(frames.count))
        let nextSignature = displayedModels.map(\.signature)
        if pollSignature != nextSignature || pollViews.count != displayedModels.count {
            clearPollViews()
            pollSignature = nextSignature
            for _ in displayedModels {
                let pollView = FirePostPollView()
                pollContainerView.addSubview(pollView)
                pollViews.append(pollView)
            }
        }

        for (index, pollView) in pollViews.enumerated() {
            guard index < displayedModels.count,
                  index < polls.count,
                  index < frames.count else {
                pollView.isHidden = true
                continue
            }
            let model = displayedModels[index]
            let poll = polls[index]
            pollView.isHidden = false
            pollView.frame = Self.relativeImageFrame(
                frame: frames[index],
                containerFrame: containerFrame
            )
            pollView.configure(
                model: model,
                canInteract: canInteract,
                isMutating: isMutating,
                onSubmit: { [weak self] selectedOptions in
                    guard let self,
                          let payload = self.currentPayload,
                          let callbacks = self.currentCallbacks else {
                        return
                    }
                    callbacks.onVotePoll(payload.post, poll, selectedOptions)
                },
                onRemoveVote: { [weak self] in
                    guard let self,
                          let payload = self.currentPayload,
                          let callbacks = self.currentCallbacks else {
                        return
                    }
                    callbacks.onUnvotePoll(payload.post, poll)
                }
            )
        }
    }

    private func clearPollViews() {
        pollViews.forEach { $0.removeFromSuperview() }
        pollViews = []
        pollSignature = []
    }

    @objc
    private func handleImageTap(_ gestureRecognizer: UITapGestureRecognizer) {
        guard let tappedView = gestureRecognizer.view,
              let payload = currentPayload,
              tappedView.tag >= 0,
              tappedView.tag < payload.renderContent.imageAttachments.count,
              let callbacks = currentCallbacks else {
            return
        }

        callbacks.onOpenImage(payload.renderContent.imageAttachments[tappedView.tag])
    }

    // MARK: - Menu

    private func buildMenu(for post: TopicPostState, callbacks: FirePostCellCallbacks, canWrite: Bool, isMutating: Bool) -> UIMenu {
        var actions: [UIMenu] = []

        if post.canEdit {
            let edit = UIAction(title: "编辑", image: UIImage(systemName: "pencil")) { [weak self] _ in
                guard self != nil else { return }
                callbacks.onEditPost(post)
            }
            edit.attributes = isMutating ? .disabled : []
            actions.append(UIMenu(options: .displayInline, children: [edit]))
        }

        var interactionActions: [UIAction] = []
        if canWrite && !post.hidden {
            let bookmarkTitle = post.bookmarked ? "编辑书签" : "添加书签"
            let bookmarkIcon = post.bookmarked ? "bookmark.fill" : "bookmark"
            let bookmark = UIAction(title: bookmarkTitle, image: UIImage(systemName: bookmarkIcon)) { _ in
                callbacks.onBookmarkPost(post)
            }
            bookmark.attributes = isMutating ? .disabled : []
            interactionActions.append(bookmark)

            let flag = UIAction(title: "举报", image: UIImage(systemName: "flag")) { _ in
                callbacks.onFlagPost(post)
            }
            flag.attributes = isMutating ? .disabled : []
            interactionActions.append(flag)
        }

        if post.canRecover {
            let recover = UIAction(title: "恢复", image: UIImage(systemName: "arrow.uturn.backward")) { _ in
                callbacks.onRecoverPost(post)
            }
            recover.attributes = isMutating ? .disabled : []
            interactionActions.append(recover)
        }

        if post.canDelete && !post.hidden {
            let delete = UIAction(title: "删除", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                callbacks.onDeletePost(post)
            }
            delete.attributes = isMutating ? [.disabled, .destructive] : .destructive
            interactionActions.append(delete)
        }

        if !interactionActions.isEmpty {
            actions.append(UIMenu(options: .displayInline, children: interactionActions))
        }

        return UIMenu(children: actions)
    }

    // MARK: - Reactions

    private func rebuildReactionCapsules(post: TopicPostState, canWrite: Bool, isMutating: Bool) {
        clearReactionCapsules()
        let canChangeReaction = canWrite && !isMutating && (post.currentUserReaction?.canUndo ?? true)

        for reaction in post.reactions {
            let option = FireTopicPresentation.reactionOption(for: reaction.id)
            let isMine = post.currentUserReaction?.id == reaction.id

            let button = UIButton(type: .system)
            let symbolString = option.symbol
            let countString = "\(reaction.count)"
            var configuration = UIButton.Configuration.plain()
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
            button.configuration = configuration
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.setAttributedTitle(
                reactionAttributedTitle(symbol: symbolString, count: countString, isMine: isMine),
                for: .normal
            )

            if isMine {
                button.setTitleColor(Self.accentTextColor, for: .normal)
                button.backgroundColor = Self.accentTextColor.withAlphaComponent(0.18)
                button.layer.borderWidth = 1
                button.layer.borderColor = Self.accentTextColor.withAlphaComponent(0.85).cgColor
            } else {
                button.setTitleColor(.secondaryLabel, for: .normal)
                button.backgroundColor = .tertiarySystemFill
                button.layer.borderWidth = 0
            }

            button.layer.cornerRadius = 14
            button.layer.masksToBounds = true
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            button.setContentHuggingPriority(.required, for: .horizontal)

            button.isAccessibilityElement = true
            button.accessibilityLabel = "\(option.label) \(reaction.count)"
            if isMine {
                button.accessibilityTraits.insert(.selected)
            }

            let reactionID = reaction.id
            button.addAction(UIAction { [weak self] _ in
                guard let self,
                      let payload = self.currentPayload,
                      let callbacks = self.currentCallbacks else { return }
                if reactionID == "heart" {
                    callbacks.onToggleLike(payload.post)
                } else {
                    callbacks.onSelectReaction(payload.post, reactionID)
                }
            }, for: .touchUpInside)
            button.isEnabled = canChangeReaction

            reactionStack.addArrangedSubview(button)
        }
    }

    private func clearReactionCapsules() {
        for arrangedSubview in reactionStack.arrangedSubviews {
            reactionStack.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }
    }

    private static func reactionSignature(post: TopicPostState, canWrite: Bool, isMutating: Bool) -> String {
        let reactions = post.reactions.map { reaction in
            [
                reaction.id,
                String(reaction.count),
                String(reaction.canUndo ?? true),
            ].joined(separator: ":")
        }.joined(separator: "|")
        return [
            reactions,
            post.currentUserReaction?.id ?? "",
            String(post.currentUserReaction?.canUndo ?? true),
            String(canWrite),
            String(isMutating),
        ].joined(separator: "\u{1F}")
    }

    private func acceptedAnswerAttributedText() -> NSAttributedString {
        let font = acceptedAnswerLabel.font ?? UIFont.preferredFont(forTextStyle: .caption2)
        let result = NSMutableAttributedString()

        if let image = UIImage(
            systemName: "checkmark.circle.fill",
            withConfiguration: UIImage.SymbolConfiguration(font: font)
        )?.withTintColor(.systemGreen, renderingMode: .alwaysOriginal) {
            result.append(NSAttributedString(attachment: NSTextAttachment(image: image)))
            result.append(NSAttributedString(string: " "))
        }

        result.append(NSAttributedString(
            string: "已采纳",
            attributes: [
                .font: font,
                .foregroundColor: UIColor.systemGreen,
            ]
        ))
        return result
    }

    private func reactionAttributedTitle(
        symbol: String,
        count: String,
        isMine: Bool
    ) -> NSAttributedString {
        let captionFont = UIFont.preferredFont(forTextStyle: .caption1)
        let countFont = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: UIFont.monospacedDigitSystemFont(
                ofSize: captionFont.pointSize,
                weight: isMine ? .semibold : .regular
            )
        )
        let color = isMine ? Self.accentTextColor : UIColor.secondaryLabel
        let result = NSMutableAttributedString(
            string: "\(symbol) ",
            attributes: [
                .font: captionFont,
                .foregroundColor: color,
            ]
        )
        result.append(NSAttributedString(
            string: count,
            attributes: [
                .font: countFont,
                .foregroundColor: color,
            ]
        ))
        return result
    }

    // MARK: - Swipe to Reply

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === swipeGestureRecognizer,
              currentPayload?.canWriteInteractions == true,
              let panGestureRecognizer = gestureRecognizer as? UIPanGestureRecognizer else {
            return false
        }

        let startLocation = panGestureRecognizer.location(in: self)
        let velocity = panGestureRecognizer.velocity(in: self)
        let resolvedAxis = FireTopicReplySwipePolicy.resolvedAxis(
            startLocationX: startLocation.x,
            translationWidth: velocity.x,
            translationHeight: velocity.y
        )
        return resolvedAxis == .horizontal && velocity.x > 0
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === swipeGestureRecognizer else {
            return true
        }

        var view: UIView? = touch.view
        while let current = view {
            if current is UIControl {
                return false
            }
            view = current.superview
        }
        return true
    }

    @objc
    private func handleSwipePan(_ gestureRecognizer: UIPanGestureRecognizer) {
        guard currentPayload?.canWriteInteractions == true else {
            resetSwipeState(animated: true)
            return
        }

        switch gestureRecognizer.state {
        case .began, .changed:
            let translation = gestureRecognizer.translation(in: self)
            let horizontalOffset = max(translation.x, 0)
            let dampenedOffset: CGFloat
            if horizontalOffset > Self.replySwipeTriggerThreshold {
                dampenedOffset = Self.replySwipeTriggerThreshold
                    + (horizontalOffset - Self.replySwipeTriggerThreshold) * 0.25
            } else {
                dampenedOffset = horizontalOffset
            }

            let resolvedOffset = min(dampenedOffset, Self.replySwipeMaxOffset)
            applySwipeOffset(resolvedOffset)

            let shouldTriggerReply = resolvedOffset >= Self.replySwipeTriggerThreshold
            if shouldTriggerReply && !replyTriggered {
                replyTriggered = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } else if !shouldTriggerReply {
                replyTriggered = false
            }
            updateReplyIndicatorAppearance()

        case .ended:
            let shouldTriggerReply = replyTriggered
            let post = currentPayload?.post
            let callbacks = currentCallbacks
            resetSwipeState(animated: true)
            if shouldTriggerReply, let post, let callbacks {
                callbacks.onSwipeReply(post)
            }

        case .cancelled, .failed:
            resetSwipeState(animated: true)

        default:
            break
        }
    }

    private func applySwipeOffset(_ offset: CGFloat) {
        swipeOffset = offset
        contentView.transform = CGAffineTransform(translationX: offset, y: 0)
        updateReplyIndicatorAppearance()
    }

    private func resetSwipeState(animated: Bool) {
        let updates = {
            self.swipeOffset = 0
            self.replyTriggered = false
            self.contentView.transform = .identity
            self.updateReplyIndicatorAppearance()
        }

        if animated {
            UIView.animate(
                withDuration: 0.22,
                delay: 0,
                usingSpringWithDamping: 0.78,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: updates
            )
        } else {
            updates()
        }
    }

    private func updateReplyIndicatorAppearance() {
        guard swipeOffset > 4 else {
            replyIndicatorView.alpha = 0
            replyIndicatorView.transform = .identity
            applyColors()
            return
        }

        let progress = min(swipeOffset / Self.replySwipeTriggerThreshold, 1)
        replyIndicatorView.alpha = Double(
            min(swipeOffset / (Self.replySwipeTriggerThreshold * 0.5), 1)
        )
        replyIndicatorView.transform = CGAffineTransform(scaleX: max(progress, 0.01), y: max(progress, 0.01))
        applyColors()
    }

    private func unionFrame(for frames: [CGRect]) -> CGRect {
        guard let firstFrame = frames.first else {
            return .zero
        }

        return frames.dropFirst().reduce(firstFrame) { partialResult, frame in
            partialResult.union(frame)
        }
    }

    // MARK: - Trait Changes

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            applyTypography()
        }
        applyColors()
    }
}
