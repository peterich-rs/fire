import AsyncDisplayKit
import UIKit

final class FirePostCellNode: ASCellNode {
    private static let replySwipeTriggerThreshold: CGFloat = 55

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

    // MARK: - Nodes

    private let avatarNode = ASNetworkImageNode()
    private let avatarMonogramNode = ASTextNode()
    private let avatarContainerNode = ASDisplayNode()
    private let threadLineNode = ASDisplayNode()
    private let usernameNode = ASTextNode()
    private let replyContextNode = ASButtonNode()
    private let timestampNode = ASTextNode()
    private let acceptedAnswerNode = ASTextNode()
    private let postNumberNode = ASTextNode()
    private let menuNode = ASButtonNode()
    private let bodyTextNode = ASTextNode()
    private let imageContainerNode = ASDisplayNode()
    private let pollContainerNode = ASDisplayNode()
    private let replyShortcutNode = ASButtonNode()
    private let reactionContainerNode = ASDisplayNode()
    private let dividerNode = ASDisplayNode()

    // MARK: - State

    private var currentPayload: FirePostCellRenderPayload?
    private var currentCallbacks: FirePostCellCallbacks?
    private var currentDepth: Int = 0
    private var currentShowsThreadLine: Bool = false
    private var currentShowsDivider: Bool = false
    private var currentAvatarSize: CGFloat = 32
    private var currentAvatarSpacing: CGFloat = 10
    private var currentLayoutWidth: CGFloat = 0
    private var currentContentSizeCategory: UIContentSizeCategory = .large
    private var renderedContentID: String?
    private var imageNodes: [FirePostImageNode] = []
    private var imageSignature: [String] = []
    private var pollViews: [FirePostPollView] = []
    private var pollHeights: [CGFloat] = []
    private var pollSignature: [String] = []
    private var pollWidth: CGFloat = 0
    private var reactionButtons: [ASButtonNode] = []
    private var reactionSignature: String?
    private var linkDelegate: RichTextNodeLinkDelegate?
    private lazy var swipeGestureRecognizer = UIPanGestureRecognizer(
        target: self,
        action: #selector(handleSwipePan(_:))
    )

    // MARK: - Init

    override init() {
        super.init()
        automaticallyManagesSubnodes = true
        setupNodes()
    }

    override func didLoad() {
        super.didLoad()
        swipeGestureRecognizer.cancelsTouchesInView = false
        view.addGestureRecognizer(swipeGestureRecognizer)
    }

    private func setupNodes() {
        backgroundColor = .systemBackground

        // Avatar
        avatarContainerNode.clipsToBounds = true
        avatarContainerNode.cornerRadius = 16
        avatarContainerNode.backgroundColor = .systemBlue
        avatarNode.contentMode = .scaleAspectFill
        avatarNode.clipsToBounds = true
        avatarNode.cornerRadius = 16
        avatarNode.isHidden = true
        avatarNode.alpha = 0
        avatarNode.delegate = self
        avatarMonogramNode.isLayerBacked = true
        avatarContainerNode.automaticallyManagesSubnodes = true
        avatarContainerNode.layoutSpecBlock = { [weak self] _, _ in
            guard let self else { return ASLayoutSpec() }
            let monogramSpec = ASCenterLayoutSpec(
                centeringOptions: .XY,
                sizingOptions: [],
                child: self.avatarMonogramNode
            )
            guard !self.avatarNode.isHidden else {
                return monogramSpec
            }
            let avatarSpec = ASCenterLayoutSpec(
                centeringOptions: .XY,
                sizingOptions: [],
                child: self.avatarNode
            )
            return ASOverlayLayoutSpec(child: monogramSpec, overlay: avatarSpec)
        }

        // Thread line
        threadLineNode.backgroundColor = .separator
        threadLineNode.isHidden = true

        // Meta
        usernameNode.maximumNumberOfLines = 1
        usernameNode.truncationMode = .byTruncatingTail
        usernameNode.isLayerBacked = true

        replyContextNode.titleNode.maximumNumberOfLines = 1
        replyContextNode.titleNode.truncationMode = .byTruncatingTail
        replyContextNode.contentEdgeInsets = .zero
        replyContextNode.addTarget(self, action: #selector(handleReplyContextTap), forControlEvents: .touchUpInside)
        replyContextNode.isHidden = true

        timestampNode.isLayerBacked = true
        acceptedAnswerNode.isHidden = true
        acceptedAnswerNode.isLayerBacked = true
        postNumberNode.isLayerBacked = true

        menuNode.isHidden = true
        menuNode.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        menuNode.addTarget(self, action: #selector(handleMenuTap), forControlEvents: .touchUpInside)
        menuNode.accessibilityLabel = "帖子操作"

        // Body text
        bodyTextNode.linkAttributeNames = [NSAttributedString.Key.link.rawValue]
        bodyTextNode.passthroughNonlinkTouches = true
        bodyTextNode.alwaysHandleTruncationTokenTap = true
        bodyTextNode.isUserInteractionEnabled = true
        bodyTextNode.placeholderEnabled = true
        bodyTextNode.placeholderColor = .tertiarySystemFill

        // Images
        imageContainerNode.isHidden = true

        // Polls
        pollContainerNode.isHidden = true

        // Reply shortcut
        replyShortcutNode.isHidden = true
        replyShortcutNode.addTarget(self, action: #selector(handleReplyShortcutTap), forControlEvents: .touchUpInside)
        replyShortcutNode.accessibilityLabel = "查看更多回复"

        // Reactions
        reactionContainerNode.isHidden = true

        // Divider
        dividerNode.backgroundColor = .separator
        dividerNode.isHidden = true
    }

    // MARK: - Configure

    func configure(
        payload: FirePostCellRenderPayload,
        callbacks: FirePostCellCallbacks,
        depth: Int,
        showsThreadLine: Bool,
        showsDivider: Bool
    ) {
        currentPayload = payload
        currentCallbacks = callbacks
        currentDepth = depth
        currentShowsThreadLine = showsThreadLine
        currentShowsDivider = showsDivider
        currentLayoutWidth = payload.layoutWidth
        currentContentSizeCategory = UIApplication.shared.preferredContentSizeCategory

        let vd = FirePostCellLayoutCalculator.visualDepth(for: depth)
        let avatarSz = vd > 0 ? FirePostCellLayoutCalculator.avatarSizeNested : FirePostCellLayoutCalculator.avatarSizeRoot
        let avatarSp = vd > 0 ? FirePostCellLayoutCalculator.avatarSpacingNested : FirePostCellLayoutCalculator.avatarSpacingRoot
        currentAvatarSize = avatarSz
        currentAvatarSpacing = avatarSp

        avatarContainerNode.cornerRadius = avatarSz / 2
        avatarNode.cornerRadius = avatarSz / 2
        avatarContainerNode.style.preferredSize = CGSize(width: avatarSz, height: avatarSz)
        avatarNode.style.preferredSize = CGSize(width: avatarSz, height: avatarSz)

        configureAvatar(payload: payload, avatarSize: avatarSz)
        configureThreadLine(shows: showsThreadLine)
        configureMeta(payload: payload)
        configureBodyText(payload: payload)
        configureImages(payload: payload)
        configurePolls(payload: payload)
        configureReplyShortcut(payload: payload)
        configureReactions(payload: payload)
        configureDivider(shows: showsDivider)
    }

    private func configureAvatar(payload: FirePostCellRenderPayload, avatarSize: CGFloat) {
        let username = payload.post.username.isEmpty ? "?" : payload.post.username
        let monogram = monogramForUsername(username: username)
        avatarMonogramNode.attributedText = NSAttributedString(
            string: monogram,
            attributes: [
                .font: UIFont.systemFont(ofSize: avatarSize * 0.36, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
        )
        avatarMonogramNode.isHidden = false
        avatarNode.isHidden = true
        avatarNode.alpha = 0

        let avatarURL = fireAvatarURL(
            avatarTemplate: payload.post.avatarTemplate,
            size: avatarSize,
            scale: UIScreen.main.scale,
            baseURLString: payload.baseURLString
        )
        if let avatarURL {
            avatarNode.isHidden = false
            avatarNode.alpha = 0
            avatarNode.setURL(avatarURL, resetToDefault: true)
        } else {
            avatarNode.isHidden = true
            avatarNode.setURL(nil, resetToDefault: true)
        }
    }

    private func configureThreadLine(shows: Bool) {
        threadLineNode.isHidden = !shows
        threadLineNode.style.preferredSize = CGSize(width: 1, height: shows ? 1 : 0)
        threadLineNode.style.flexGrow = shows ? 1.0 : 0.0
    }

    private func configureMeta(payload: FirePostCellRenderPayload) {
        let subheadlineFont = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: UIFont.systemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize,
                weight: .semibold
            )
        )
        let captionFont = UIFont.preferredFont(forTextStyle: .caption2)
        let monoCaptionFont = UIFontMetrics(forTextStyle: .caption2).scaledFont(
            for: UIFont.monospacedDigitSystemFont(
                ofSize: captionFont.pointSize,
                weight: .regular
            )
        )

        usernameNode.attributedText = NSAttributedString(
            string: payload.post.username.isEmpty ? "Unknown" : payload.post.username,
            attributes: [.font: subheadlineFont, .foregroundColor: UIColor.label]
        )

        if let replyContext = payload.replyContext,
           let targetPN = payload.replyTargetPostNumber, targetPN > 0 {
            replyContextNode.isHidden = false
            replyContextNode.setAttributedTitle(NSAttributedString(
                string: replyContext,
                attributes: [.font: subheadlineFont, .foregroundColor: Self.accentTextColor]
            ), for: .normal)
        } else {
            replyContextNode.isHidden = true
            replyContextNode.setAttributedTitle(nil, for: .normal)
        }

        timestampNode.attributedText = NSAttributedString(
            string: FireTopicPresentation.compactTimestamp(payload.post.createdAt) ?? "",
            attributes: [.font: captionFont, .foregroundColor: Self.tertiaryInkColor]
        )

        if payload.post.acceptedAnswer {
            acceptedAnswerNode.isHidden = false
            acceptedAnswerNode.attributedText = acceptedAnswerAttributedText()
        } else {
            acceptedAnswerNode.isHidden = true
        }

        postNumberNode.attributedText = NSAttributedString(
            string: "#\(payload.post.postNumber)",
            attributes: [.font: monoCaptionFont, .foregroundColor: Self.tertiaryInkColor]
        )

        let canShowMenu = payload.post.canEdit
            || (payload.canWriteInteractions && !payload.post.hidden)
            || payload.post.canRecover
            || (payload.post.canDelete && !payload.post.hidden)
        menuNode.isHidden = !canShowMenu
        menuNode.isEnabled = canShowMenu
    }

    private func configureBodyText(payload: FirePostCellRenderPayload) {
        guard let attrText = payload.renderContent.attributedText, attrText.length > 0 else {
            bodyTextNode.attributedText = nil
            bodyTextNode.isHidden = true
            return
        }

        let contentID = "post:\(payload.post.id)|render:\(payload.renderContent.signature.token)"
        let isCollapsed = payload.textExpansionState.isCollapsed

        if renderedContentID != contentID {
            renderedContentID = contentID
            bodyTextNode.attributedText = attrText
        }
        bodyTextNode.isHidden = false
        bodyTextNode.maximumNumberOfLines = isCollapsed
            ? UInt(FirePostTextExpansionState.collapsedLineLimit)
            : 0
        bodyTextNode.truncationAttributedText = isCollapsed
            ? Self.expansionTruncationToken()
            : nil

        linkDelegate = RichTextNodeLinkDelegate(
            onLink: { [weak self] url in
                self?.currentCallbacks?.onLinkTapped(url)
            },
            onTruncation: { [weak self] in
                guard let self, let payload = self.currentPayload, let callbacks = self.currentCallbacks else { return }
                callbacks.onExpandText(payload.post)
            }
        )
        bodyTextNode.delegate = linkDelegate
    }

    private func configureImages(payload: FirePostCellRenderPayload) {
        let images = payload.renderContent.imageAttachments
        let nextSignature = images.map(\.id)

        guard !images.isEmpty else {
            imageContainerNode.isHidden = true
            rebuildImageNodes([])
            return
        }

        imageContainerNode.isHidden = false
        let availableWidth = Self.availableContentWidth(
            totalWidth: payload.layoutWidth,
            depth: currentDepth,
            avatarSize: currentAvatarSize,
            avatarSpacing: currentAvatarSpacing
        )
        let renderSizes = images.map { image in
            FirePostCellLayoutCalculator.imageRenderSize(
                for: image,
                availableWidth: availableWidth,
                depth: currentDepth
            )
        }
        if imageSignature != nextSignature {
            rebuildImageNodes(images, renderSizes: renderSizes)
            imageSignature = nextSignature
        } else {
            for (imageNode, renderSize) in zip(imageNodes, renderSizes) {
                imageNode.updateRenderSize(renderSize)
            }
        }
    }

    private func rebuildImageNodes(_ images: [FireCookedImage], renderSizes: [CGSize] = []) {
        for node in imageNodes {
            node.removeFromSupernode()
        }
        imageNodes.removeAll()
        imageSignature = images.map(\.id)

        for (index, image) in images.enumerated() {
            let renderSize = index < renderSizes.count
                ? renderSizes[index]
                : CGSize(width: 1, height: 1)
            let imageNode = FirePostImageNode(image: image, renderSize: renderSize)
            imageNode.style.spacingBefore = 10
            imageNode.addTarget(self, action: #selector(handleImageTap(_:)), forControlEvents: .touchUpInside)
            imageNodes.append(imageNode)
        }
    }

    private func configurePolls(payload: FirePostCellRenderPayload) {
        let pollModels = FirePostPollRenderModel.models(from: payload.post.polls)
        guard !pollModels.isEmpty else {
            pollContainerNode.isHidden = true
            rebuildPollViews([], [], payload: payload)
            return
        }

        pollContainerNode.isHidden = false
        let nextSignature = pollModels.map(\.signature)
        let availableWidth = Self.availableContentWidth(
            totalWidth: payload.layoutWidth,
            depth: currentDepth,
            avatarSize: currentAvatarSize,
            avatarSpacing: currentAvatarSpacing
        )
        if pollSignature != nextSignature || abs(pollWidth - availableWidth) > 0.5 {
            rebuildPollViews(payload.post.polls, pollModels, payload: payload, availableWidth: availableWidth)
            pollSignature = nextSignature
            pollWidth = availableWidth
        }
    }

    private func rebuildPollViews(
        _ polls: [PollState],
        _ models: [FirePostPollRenderModel],
        payload: FirePostCellRenderPayload,
        availableWidth: CGFloat? = nil
    ) {
        for view in pollViews {
            view.removeFromSuperview()
        }
        pollViews.removeAll()
        pollHeights.removeAll()
        let width = availableWidth ?? Self.availableContentWidth(
            totalWidth: payload.layoutWidth,
            depth: currentDepth,
            avatarSize: currentAvatarSize,
            avatarSpacing: currentAvatarSpacing
        )

        for (index, model) in models.enumerated() {
            guard index < polls.count else { break }
            let pollView = FirePostPollView()
            let poll = polls[index]
            pollView.configure(
                model: model,
                canInteract: payload.canWriteInteractions,
                isMutating: payload.isMutating,
                onSubmit: { [weak self] selectedOptions in
                    guard let self, let p = self.currentPayload, let callbacks = self.currentCallbacks else { return }
                    callbacks.onVotePoll(p.post, poll, selectedOptions)
                },
                onRemoveVote: { [weak self] in
                    guard let self, let p = self.currentPayload, let callbacks = self.currentCallbacks else { return }
                    callbacks.onUnvotePoll(p.post, poll)
                }
            )
            pollContainerNode.view.addSubview(pollView)
            pollViews.append(pollView)
            pollHeights.append(FirePostPollView.preferredHeight(
                for: model,
                availableWidth: width,
                contentSizeCategory: UIApplication.shared.preferredContentSizeCategory
            ))
        }
        let totalPollHeight = pollHeights.reduce(0, +) + CGFloat(max(pollHeights.count - 1, 0)) * 10
        pollContainerNode.style.preferredSize = CGSize(width: 1, height: ceil(totalPollHeight))
    }

    private func configureReplyShortcut(payload: FirePostCellRenderPayload) {
        guard let count = payload.replyShortcutCount else {
            replyShortcutNode.isHidden = true
            return
        }
        replyShortcutNode.isHidden = false
        replyShortcutNode.isEnabled = !payload.isLoadingReplyContext
        let title = payload.isLoadingReplyContext
            ? "正在加载回复..."
            : (count > 0 ? "查看更多 \(count) 条回复" : "查看更多回复")
        replyShortcutNode.setAttributedTitle(NSAttributedString(
            string: title,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .caption1),
                .foregroundColor: Self.accentTextColor,
            ]
        ), for: .normal)
        replyShortcutNode.accessibilityLabel = title
    }

    private func configureReactions(payload: FirePostCellRenderPayload) {
        guard !payload.post.reactions.isEmpty else {
            reactionContainerNode.isHidden = true
            rebuildReactionButtons([], payload: payload)
            return
        }

        reactionContainerNode.isHidden = false
        let nextSig = Self.reactionSignatureString(
            post: payload.post,
            canWrite: payload.canWriteInteractions,
            isMutating: payload.isMutating
        )
        if reactionSignature != nextSig {
            rebuildReactionButtons(payload.post.reactions, payload: payload)
            reactionSignature = nextSig
        }
    }

    private func rebuildReactionButtons(_ reactions: [TopicReactionState], payload: FirePostCellRenderPayload) {
        for button in reactionButtons {
            button.removeFromSupernode()
        }
        reactionButtons.removeAll()

        let canChangeReaction = payload.canWriteInteractions
            && !payload.isMutating
            && (payload.post.currentUserReaction?.canUndo ?? true)

        for reaction in reactions {
            let option = FireTopicPresentation.reactionOption(for: reaction.id)
            let isMine = payload.post.currentUserReaction?.id == reaction.id
            let button = ASButtonNode()
            let symbolString = option.symbol
            let countString = "\(reaction.count)"
            let captionFont = UIFont.preferredFont(forTextStyle: .caption1)
            let countFont = UIFontMetrics(forTextStyle: .caption1).scaledFont(
                for: UIFont.monospacedDigitSystemFont(
                    ofSize: captionFont.pointSize,
                    weight: isMine ? .semibold : .regular
                )
            )
            let color = isMine ? Self.accentTextColor : UIColor.secondaryLabel
            let title = NSMutableAttributedString(
                string: "\(symbolString) ",
                attributes: [.font: captionFont, .foregroundColor: color]
            )
            title.append(NSAttributedString(
                string: countString,
                attributes: [.font: countFont, .foregroundColor: color]
            ))
            button.setAttributedTitle(title, for: .normal)
            button.cornerRadius = 14
            button.clipsToBounds = true
            button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
            button.backgroundColor = isMine
                ? Self.accentTextColor.withAlphaComponent(0.18)
                : .tertiarySystemFill
            if isMine {
                button.borderColor = Self.accentTextColor.withAlphaComponent(0.85).cgColor
                button.borderWidth = 1
            }
            button.isEnabled = canChangeReaction
            button.accessibilityLabel = "\(option.label) \(reaction.count)"
            if isMine {
                button.accessibilityTraits.insert(.selected)
            }

            button.addTarget(self, action: #selector(handleReactionTap(_:)), forControlEvents: .touchUpInside)

            reactionButtons.append(button)
        }
    }

    private func configureDivider(shows: Bool) {
        dividerNode.isHidden = !shows
    }

    // MARK: - Layout

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let vd = FirePostCellLayoutCalculator.visualDepth(for: currentDepth)
        let indent = CGFloat(min(vd, FirePostCellLayoutCalculator.maxVisualDepth)) * FirePostCellLayoutCalculator.indentWidthPerDepth
        let avatarSz = currentAvatarSize
        let avatarSp = currentAvatarSpacing
        let outerPadding: CGFloat = 16
        let totalWidth = constrainedSize.max.width.isFinite ? constrainedSize.max.width : currentLayoutWidth
        let shouldSuppressAttachments = (!imageNodes.isEmpty || !pollContainerNode.isHidden)
            && Self.shouldSuppressAttachmentsForCollapsedText(
                attributedText: currentPayload?.renderContent.attributedText,
                textExpansionState: currentPayload?.textExpansionState ?? .disabled,
                totalWidth: totalWidth,
                depth: currentDepth,
                avatarSize: currentAvatarSize,
                avatarSpacing: currentAvatarSpacing,
                contentSizeCategory: currentContentSizeCategory
            )

        // Avatar column
        let avatarSizeStyle = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 0,
            justifyContent: .start,
            alignItems: .center,
            children: [avatarContainerNode, threadLineNode].filter { !$0.isHidden }
        )
        avatarSizeStyle.style.minWidth = ASDimensionMake(avatarSz)
        avatarSizeStyle.style.maxWidth = ASDimensionMake(avatarSz)

        // Meta row
        let spacer = ASLayoutSpec()
        spacer.style.flexGrow = 1.0

        var metaChildren: [ASLayoutElement] = [usernameNode]
        if !replyContextNode.isHidden {
            metaChildren.append(replyContextNode)
        }
        metaChildren.append(timestampNode)
        metaChildren.append(spacer)
        if !acceptedAnswerNode.isHidden {
            metaChildren.append(acceptedAnswerNode)
        }
        metaChildren.append(postNumberNode)
        if !menuNode.isHidden {
            menuNode.style.preferredSize = CGSize(width: 20, height: 20)
            metaChildren.append(menuNode)
        }
        let metaRow = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 6,
            justifyContent: .start,
            alignItems: .center,
            children: metaChildren
        )

        // Content column
        var contentChildren: [ASLayoutElement] = [metaRow]

        if !bodyTextNode.isHidden {
            contentChildren.append(bodyTextNode)
        }

        // Image nodes
        if !shouldSuppressAttachments {
            // Image nodes
            for imageNode in imageNodes {
                contentChildren.append(imageNode)
            }

            // Poll container
            if !pollContainerNode.isHidden {
                contentChildren.append(pollContainerNode)
            }
        }

        // Reply shortcut
        if !replyShortcutNode.isHidden {
            replyShortcutNode.style.flexGrow = 0
            contentChildren.append(replyShortcutNode)
        }

        // Reactions
        if !reactionContainerNode.isHidden && !reactionButtons.isEmpty {
            let reactionRow = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: 8,
                justifyContent: .start,
                alignItems: .center,
                children: reactionButtons
            )
            contentChildren.append(reactionRow)
        }

        // Divider
        if !dividerNode.isHidden {
            let dividerWidth = Self.availableContentWidth(
                totalWidth: totalWidth,
                depth: currentDepth,
                avatarSize: currentAvatarSize,
                avatarSpacing: currentAvatarSpacing
            )
            dividerNode.style.preferredSize = CGSize(width: max(dividerWidth, 1), height: 0.5)
            contentChildren.append(dividerNode)
        }

        let contentStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 8,
            justifyContent: .start,
            alignItems: .stretch,
            children: contentChildren
        )
        contentStack.style.flexGrow = 1.0

        // Root
        let rootStack = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: avatarSp,
            justifyContent: .start,
            alignItems: .stretch,
            children: [avatarSizeStyle, contentStack]
        )

        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(
                top: 8,
                left: outerPadding + indent,
                bottom: 8,
                right: outerPadding
            ),
            child: rootStack
        )
    }

    override func layout() {
        super.layout()

        // Size poll views after layout
        let availableWidth = calculatedSize.width
            - FirePostCellLayoutCalculator.outerHorizontalPadding * 2
            - CGFloat(min(FirePostCellLayoutCalculator.visualDepth(for: currentDepth), FirePostCellLayoutCalculator.maxVisualDepth)) * FirePostCellLayoutCalculator.indentWidthPerDepth
            - currentAvatarSize
            - currentAvatarSpacing

        var pollY: CGFloat = 0
        for (index, pollView) in pollViews.enumerated() {
            let height = index < pollHeights.count ? pollHeights[index] : 0
            pollView.frame = CGRect(
                x: 0,
                y: pollY,
                width: availableWidth,
                height: height
            )
            pollY += height + 10
        }
    }

    // MARK: - Actions

    @objc private func handleReplyContextTap() {
        guard let payload = currentPayload,
              let postNumber = payload.replyTargetPostNumber,
              postNumber > 0,
              let callbacks = currentCallbacks else {
            return
        }
        callbacks.onOpenReplyTarget(postNumber)
    }

    @objc private func handleReplyShortcutTap() {
        guard let payload = currentPayload,
              !payload.isLoadingReplyContext,
              let callbacks = currentCallbacks else {
            return
        }
        callbacks.onOpenReplies(payload.post)
    }

    @objc private func handleImageTap(_ sender: FirePostImageNode) {
        currentCallbacks?.onOpenImage(sender.image)
    }

    @objc private func handleSwipePan(_ gestureRecognizer: UIPanGestureRecognizer) {
        guard gestureRecognizer.state == .ended,
              let payload = currentPayload,
              let callbacks = currentCallbacks else {
            return
        }
        let translation = gestureRecognizer.translation(in: view)
        guard translation.x > Self.replySwipeTriggerThreshold,
              abs(translation.x) > abs(translation.y) else {
            return
        }
        callbacks.onSwipeReply(payload.post)
    }

    @objc private func handleMenuTap() {
        guard let payload = currentPayload,
              let callbacks = currentCallbacks,
              let presenter = nearestViewController() else {
            return
        }
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let post = payload.post
        let isMutating = payload.isMutating
        if post.canEdit {
            alert.addAction(UIAlertAction(title: "编辑", style: .default) { _ in
                callbacks.onEditPost(post)
            })
        }
        if payload.canWriteInteractions && !post.hidden {
            alert.addAction(UIAlertAction(title: post.bookmarked ? "编辑书签" : "添加书签", style: .default) { _ in
                callbacks.onBookmarkPost(post)
            })
            alert.addAction(UIAlertAction(title: "举报", style: .default) { _ in
                callbacks.onFlagPost(post)
            })
        }
        if post.canRecover {
            alert.addAction(UIAlertAction(title: "恢复", style: .default) { _ in
                callbacks.onRecoverPost(post)
            })
        }
        if post.canDelete && !post.hidden {
            alert.addAction(UIAlertAction(title: "删除", style: .destructive) { _ in
                callbacks.onDeletePost(post)
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.actions.forEach { action in
            if action.style != .cancel {
                action.isEnabled = !isMutating
            }
        }
        alert.popoverPresentationController?.sourceView = menuNode.view
        alert.popoverPresentationController?.sourceRect = menuNode.view.bounds
        presenter.present(alert, animated: true)
    }

    @objc private func handleReactionTap(_ sender: ASButtonNode) {
        guard let index = reactionButtons.firstIndex(of: sender),
              let payload = currentPayload,
              let callbacks = currentCallbacks,
              index < payload.post.reactions.count else {
            return
        }
        let reaction = payload.post.reactions[index]
        if reaction.id == "heart" {
            callbacks.onToggleLike(payload.post)
        } else {
            callbacks.onSelectReaction(payload.post, reaction.id)
        }
    }

    // MARK: - Menu

    private func buildMenu(for post: TopicPostState, callbacks: FirePostCellCallbacks, canWrite: Bool, isMutating: Bool) -> UIMenu {
        var actions: [UIMenu] = []

        if post.canEdit {
            let edit = UIAction(title: "编辑", image: UIImage(systemName: "pencil")) { _ in
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

    // MARK: - Helpers

    private func acceptedAnswerAttributedText() -> NSAttributedString {
        let font = UIFontMetrics(forTextStyle: .caption2).scaledFont(
            for: UIFont.systemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .caption2).pointSize,
                weight: .medium
            )
        )
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
            attributes: [.font: font, .foregroundColor: UIColor.systemGreen]
        ))
        return result
    }

    private static func expansionTruncationToken() -> NSAttributedString {
        let font = UIFont.preferredFont(forTextStyle: .subheadline)
        let result = NSMutableAttributedString(
            string: "... ",
            attributes: [.font: font, .foregroundColor: UIColor.label]
        )
        result.append(NSAttributedString(
            string: "展开",
            attributes: [.font: font, .foregroundColor: accentTextColor]
        ))
        return result
    }

    private static func reactionSignatureString(post: TopicPostState, canWrite: Bool, isMutating: Bool) -> String {
        let reactions = post.reactions.map { reaction in
            [reaction.id, String(reaction.count), String(reaction.canUndo ?? true)].joined(separator: ":")
        }.joined(separator: "|")
        return [
            reactions,
            post.currentUserReaction?.id ?? "",
            String(post.currentUserReaction?.canUndo ?? true),
            String(canWrite),
            String(isMutating),
        ].joined(separator: "\u{1F}")
    }

    private static func availableContentWidth(
        totalWidth: CGFloat,
        depth: Int,
        avatarSize: CGFloat,
        avatarSpacing: CGFloat
    ) -> CGFloat {
        let vd = FirePostCellLayoutCalculator.visualDepth(for: depth)
        let indent = CGFloat(min(vd, FirePostCellLayoutCalculator.maxVisualDepth))
            * FirePostCellLayoutCalculator.indentWidthPerDepth
        return max(
            totalWidth
                - FirePostCellLayoutCalculator.outerHorizontalPadding * 2
                - indent
                - avatarSize
                - avatarSpacing,
            1
        )
    }

    static func shouldSuppressAttachmentsForCollapsedText(
        attributedText: NSAttributedString?,
        textExpansionState: FirePostTextExpansionState,
        totalWidth: CGFloat,
        depth: Int,
        avatarSize: CGFloat,
        avatarSpacing: CGFloat,
        contentSizeCategory: UIContentSizeCategory
    ) -> Bool {
        guard textExpansionState.isCollapsed else {
            return false
        }
        let availableWidth = availableContentWidth(
            totalWidth: totalWidth,
            depth: depth,
            avatarSize: avatarSize,
            avatarSpacing: avatarSpacing
        )
        guard let textHeight = FirePostCellLayoutCalculator.measureRichTextHeight(
            attributedText: attributedText,
            containerWidth: availableWidth,
            contentSizeCategory: contentSizeCategory
        ) else {
            return false
        }
        return textHeight > FirePostCellLayoutCalculator.collapsedTextHeight(
            contentSizeCategory: contentSizeCategory
        )
    }

    private func showLoadedAvatar() {
        avatarNode.alpha = 1
    }

    private func showAvatarFallback() {
        avatarNode.alpha = 0
    }

    private func nearestViewController() -> UIViewController? {
        var responder: UIResponder? = view
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController
            }
            responder = current.next
        }
        return nil
    }
}

extension FirePostCellNode: ASNetworkImageNodeDelegate {
    func imageNodeDidLoadImage(fromCache imageNode: ASNetworkImageNode) {
        guard imageNode === avatarNode else {
            return
        }
        showLoadedAvatar()
    }

    func imageNode(_ imageNode: ASNetworkImageNode, didLoad image: UIImage) {
        guard imageNode === avatarNode else {
            return
        }
        showLoadedAvatar()
    }

    func imageNode(_ imageNode: ASNetworkImageNode, didFailWithError error: Error) {
        guard imageNode === avatarNode else {
            return
        }
        showAvatarFallback()
    }
}

private final class FirePostImageNode: ASControlNode {
    let image: FireCookedImage
    private let imageNode = ASNetworkImageNode()
    private var renderSize: CGSize

    init(image: FireCookedImage, renderSize: CGSize) {
        self.image = image
        self.renderSize = renderSize
        super.init()
        automaticallyManagesSubnodes = true
        isUserInteractionEnabled = true
        accessibilityLabel = image.altText?.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty("帖子图片")
        accessibilityTraits = [.image, .button]

        imageNode.url = image.url
        imageNode.contentMode = .scaleAspectFit
        imageNode.clipsToBounds = true
        imageNode.cornerRadius = 16
        imageNode.borderColor = UIColor.separator.cgColor
        imageNode.borderWidth = 0.5
        imageNode.placeholderEnabled = true
        imageNode.placeholderColor = .tertiarySystemFill
        imageNode.backgroundColor = .tertiarySystemFill
        imageNode.isUserInteractionEnabled = false
        updateRenderSize(renderSize)
    }

    func updateRenderSize(_ renderSize: CGSize) {
        let didChange = self.renderSize != renderSize
        self.renderSize = renderSize
        style.preferredSize = renderSize
        imageNode.style.preferredSize = renderSize
        if didChange {
            setNeedsLayout()
        }
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let maxWidth = constrainedSize.max.width.isFinite
            ? min(renderSize.width, constrainedSize.max.width)
            : renderSize.width
        let ratio = renderSize.height / max(renderSize.width, 1)
        let boundedSize = CGSize(width: max(maxWidth, 1), height: max(maxWidth * ratio, 1))
        imageNode.style.preferredSize = boundedSize
        return ASWrapperLayoutSpec(layoutElement: imageNode)
    }
}

// MARK: - Link Delegate

private final class RichTextNodeLinkDelegate: NSObject, ASTextNodeDelegate {
    private let onLink: (URL) -> Void
    private let onTruncation: () -> Void

    init(onLink: @escaping (URL) -> Void, onTruncation: @escaping () -> Void) {
        self.onLink = onLink
        self.onTruncation = onTruncation
    }

    func textNode(_ textNode: ASTextNode, tappedLinkAttribute attribute: String, value: Any, at point: CGPoint, textRange: NSRange) {
        if let url = value as? URL {
            onLink(url)
        } else if let string = value as? String, let url = URL(string: string) {
            onLink(url)
        }
    }

    func textNodeTappedTruncationToken(_ textNode: ASTextNode) {
        onTruncation()
    }
}
