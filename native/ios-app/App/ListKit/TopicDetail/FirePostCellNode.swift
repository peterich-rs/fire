import AsyncDisplayKit
import UIKit

final class FirePostCellNode: ASCellNode, UIGestureRecognizerDelegate {
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

    private let avatarNode = ASImageNode()
    private let avatarMonogramNode = ASTextNode()
    private let avatarContainerNode = ASDisplayNode()
    private let threadLineNode = ASDisplayNode()
    private let usernameNode = ASTextNode()
    private let authorBadgeNode = ASTextNode()
    private let authorMetadataNode = ASTextNode()
    private let replyContextNode = ASButtonNode()
    private let timestampNode = ASTextNode()
    private let acceptedAnswerNode = ASTextNode()
    private let postNumberNode = ASTextNode()
    private let menuNode = ASButtonNode()
    private let bodyTextNode = ASTextNode()
    private let bodySelectableTextNode = FireSelectableRichTextNode()
    private let imageContainerNode = ASDisplayNode()
    private let pollContainerNode = ASDisplayNode()
    private let boostContainerNode = ASDisplayNode()
    private lazy var boostBarrageNode: ASDisplayNode = {
        let node = ASDisplayNode(viewBlock: {
            FirePostBoostBarrageView()
        })
        node.onDidLoad { [weak self] node in
            guard let view = node.view as? FirePostBoostBarrageView else { return }
            view.configure(
                boosts: self?.boostBarrageBoosts ?? [],
                batchSignature: self?.boostBarrageBatchSignature ?? "",
                animationsEnabled: self?.boostAnimationsEnabled ?? true
            )
        }
        return node
    }()
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
    private var currentResolvedLayout: FirePostCellLayout?
    private var currentContentSizeCategory: UIContentSizeCategory = .large
    private var renderedContentID: String?
    private var avatarSignature: String?
    private var avatarLoadTask: Task<Void, Never>?
    private var avatarLoadGeneration: UInt64 = 0
    private var contentSegmentNodes: [ASDisplayNode] = []
    private var contentSegmentSignature: [String] = []
    private var pollViews: [FirePostPollView] = []
    private var pollHeights: [CGFloat] = []
    private var pollSignature: [String] = []
    private var pollWidth: CGFloat = 0
    private lazy var boostManualScrollerNode: ASDisplayNode = {
        let node = ASDisplayNode(viewBlock: {
            FirePostBoostManualScrollerView()
        })
        node.onDidLoad { [weak self] node in
            guard let view = node.view as? FirePostBoostManualScrollerView else { return }
            view.configure(
                boosts: self?.boostManualBoosts ?? []
            )
        }
        return node
    }()
    private var boostSignature: [String] = []
    private var boostBarrageBoosts: [TopicPostBoostState] = []
    private var boostBarrageLines: [String] = []
    private var boostBarrageBatchSignature = ""
    private var boostManualBoosts: [TopicPostBoostState] = []
    private var boostAnimationsEnabled = true
    private var reactionButtons: [ASButtonNode] = []
    private var reactionButtonIDs: [String] = []
    private var displayedReactions: [TopicReactionState] = []
    private var reactionSignature: String?
    private var linkDelegate: RichTextNodeLinkDelegate?
    private lazy var swipeGestureRecognizer = UIPanGestureRecognizer(
        target: self,
        action: #selector(handleSwipePan(_:))
    )
    private lazy var avatarTapGestureRecognizer: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleProfileTap))
        gesture.cancelsTouchesInView = false
        return gesture
    }()
    private lazy var usernameTapGestureRecognizer: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleProfileTap))
        gesture.cancelsTouchesInView = false
        return gesture
    }()

    // MARK: - Init

    override init() {
        super.init()
        automaticallyManagesSubnodes = true
        setupNodes()
    }

    override func didLoad() {
        super.didLoad()
        swipeGestureRecognizer.cancelsTouchesInView = false
        swipeGestureRecognizer.delegate = self
        view.addGestureRecognizer(swipeGestureRecognizer)
        avatarContainerNode.view.addGestureRecognizer(avatarTapGestureRecognizer)
        usernameNode.view.addGestureRecognizer(usernameTapGestureRecognizer)
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let popGestureRecognizer = self.nearestViewController()?
                    .navigationController?
                    .interactivePopGestureRecognizer else {
                return
            }
            self.swipeGestureRecognizer.require(toFail: popGestureRecognizer)
        }
    }

    private func setupNodes() {
        backgroundColor = .systemBackground

        // Avatar
        avatarContainerNode.isUserInteractionEnabled = true
        avatarContainerNode.clipsToBounds = true
        avatarContainerNode.cornerRadius = 16
        avatarContainerNode.backgroundColor = .systemBlue
        avatarNode.contentMode = .scaleAspectFill
        avatarNode.clipsToBounds = true
        avatarNode.cornerRadius = 16
        avatarNode.isHidden = true
        avatarNode.alpha = 0
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
        usernameNode.style.flexShrink = 1.0
        authorBadgeNode.maximumNumberOfLines = 1
        authorBadgeNode.truncationMode = .byClipping
        authorBadgeNode.isLayerBacked = true
        authorBadgeNode.style.flexShrink = 0.0
        authorBadgeNode.isHidden = true
        authorMetadataNode.maximumNumberOfLines = 1
        authorMetadataNode.truncationMode = .byTruncatingTail
        authorMetadataNode.isLayerBacked = true
        authorMetadataNode.style.flexShrink = 1.0
        authorMetadataNode.isHidden = true

        replyContextNode.titleNode.maximumNumberOfLines = 1
        replyContextNode.titleNode.truncationMode = .byTruncatingTail
        replyContextNode.contentEdgeInsets = .zero
        replyContextNode.addTarget(self, action: #selector(handleReplyContextTap), forControlEvents: .touchUpInside)
        replyContextNode.isHidden = true
        replyContextNode.style.flexShrink = 1.0

        timestampNode.isLayerBacked = true
        acceptedAnswerNode.isHidden = true
        acceptedAnswerNode.isLayerBacked = true
        postNumberNode.isLayerBacked = true

        menuNode.isHidden = true
        menuNode.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        menuNode.addTarget(self, action: #selector(handleMenuTap), forControlEvents: .touchUpInside)
        menuNode.accessibilityLabel = "帖子操作"

        // Body text
        configureRichTextNode(bodyTextNode)
        configureSelectableTextNode(bodySelectableTextNode)

        // Images
        imageContainerNode.isHidden = true

        // Polls
        pollContainerNode.isHidden = true

        // Boosts
        boostContainerNode.isHidden = true
        boostContainerNode.automaticallyManagesSubnodes = true
        boostContainerNode.layoutSpecBlock = { [weak self] _, _ in
            guard let self, !self.boostManualScrollerNode.isHidden else { return ASLayoutSpec() }
            let scrollerSize = CGSize(
                width: max(
                    Self.availableContentWidth(
                        totalWidth: self.currentLayoutWidth,
                        depth: self.currentDepth,
                        avatarSize: self.currentAvatarSize,
                        avatarSpacing: self.currentAvatarSpacing
                    ),
                    1
                ),
                height: FirePostCellLayoutCalculator.fixedBoostManualHeight
            )
            self.boostManualScrollerNode.style.preferredSize = scrollerSize
            self.boostManualScrollerNode.style.minHeight = ASDimensionMake(scrollerSize.height)
            self.boostManualScrollerNode.style.maxHeight = ASDimensionMake(scrollerSize.height)
            return ASWrapperLayoutSpec(layoutElement: self.boostManualScrollerNode)
        }
        boostContainerNode.style.minHeight = ASDimensionMake(FirePostCellLayoutCalculator.fixedBoostManualHeight)
        boostContainerNode.style.maxHeight = ASDimensionMake(FirePostCellLayoutCalculator.fixedBoostManualHeight)
        boostContainerNode.isUserInteractionEnabled = true
        boostManualScrollerNode.isHidden = true
        boostManualScrollerNode.isUserInteractionEnabled = true
        boostBarrageNode.isHidden = true
        boostBarrageNode.isUserInteractionEnabled = false

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
        currentResolvedLayout = payload.layout
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
        configureBodyContent(payload: payload)
        configurePolls(payload: payload)
        boostAnimationsEnabled = payload.boostAnimationsEnabled
        configureBoosts(payload: payload)
        configureReplyShortcut(payload: payload)
        configureReactions(payload: payload)
        configureDivider(shows: showsDivider)
    }

    private func configureAvatar(payload: FirePostCellRenderPayload, avatarSize: CGFloat) {
        let username = payload.post.username.isEmpty ? "?" : payload.post.username
        let avatarURL = fireAvatarURL(
            avatarTemplate: payload.post.avatarTemplate,
            size: avatarSize,
            scale: UIScreen.main.scale,
            baseURLString: payload.baseURLString
        )
        let nextAvatarSignature = [
            username,
            payload.post.avatarTemplate ?? "",
            payload.baseURLString,
            avatarURL?.absoluteString ?? "monogram",
            String(Int(avatarSize.rounded())),
        ].joined(separator: "\u{1F}")
        guard avatarSignature != nextAvatarSignature else {
            return
        }
        avatarSignature = nextAvatarSignature

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

        if let avatarURL {
            avatarNode.isHidden = false
            avatarNode.alpha = 0
            loadAvatar(url: avatarURL)
        } else {
            cancelAvatarLoad()
            avatarNode.isHidden = true
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
            string: FirePostAuthorMetadataDisplay.displayName(for: payload.post),
            attributes: [.font: subheadlineFont, .foregroundColor: UIColor.label]
        )
        usernameNode.isUserInteractionEnabled = !payload.post.username.isEmpty

        let primaryBadges = FirePostAuthorMetadataDisplay.primaryBadgeParts(for: payload.post)
        if primaryBadges.isEmpty {
            authorBadgeNode.isHidden = true
            authorBadgeNode.attributedText = nil
        } else {
            authorBadgeNode.isHidden = false
            authorBadgeNode.attributedText = Self.badgeAttributedText(parts: primaryBadges)
        }

        let secondaryParts = FirePostAuthorMetadataDisplay.secondaryLineParts(for: payload.post)
        if secondaryParts.isEmpty {
            authorMetadataNode.isHidden = true
            authorMetadataNode.attributedText = nil
        } else {
            authorMetadataNode.isHidden = false
            authorMetadataNode.attributedText = NSAttributedString(
                string: secondaryParts.joined(separator: " · "),
                attributes: [
                    .font: captionFont,
                    .foregroundColor: UIColor.secondaryLabel,
                ]
            )
        }

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
            string: "#\(payload.post.postNumber)楼",
            attributes: [.font: monoCaptionFont, .foregroundColor: Self.tertiaryInkColor]
        )

        let canShowMenu = payload.post.canEdit
            || (payload.canWriteInteractions && !payload.post.hidden)
            || payload.post.canRecover
            || (payload.post.canDelete && !payload.post.hidden)
        menuNode.isHidden = !canShowMenu
        menuNode.isEnabled = canShowMenu
    }

    private func configureRichTextNode(_ node: ASTextNode) {
        node.linkAttributeNames = [NSAttributedString.Key.link.rawValue]
        node.passthroughNonlinkTouches = true
        node.alwaysHandleTruncationTokenTap = true
        node.isUserInteractionEnabled = true
        node.placeholderEnabled = true
        node.placeholderColor = .tertiarySystemFill
        node.style.flexShrink = 1.0
    }

    private func configureBodyContent(payload: FirePostCellRenderPayload) {
        let hasInlineImages = payload.renderContent.segments.contains(where: \.isImage)
        guard hasInlineImages else {
            configureBodyText(payload: payload)
            rebuildContentSegmentNodes([], renderSizes: [])
            return
        }

        guard !payload.textExpansionState.isCollapsed else {
            configureBodyText(payload: payload)
            configureImageOnlySegmentNodes(payload: payload)
            return
        }

        bodyTextNode.attributedText = nil
        bodyTextNode.isHidden = true
        bodySelectableTextNode.attributedText = nil
        bodySelectableTextNode.isHidden = true
        renderedContentID = nil
        linkDelegate = RichTextNodeLinkDelegate(
            onLink: { [weak self] url in
                self?.currentCallbacks?.onLinkTapped(url)
            },
            onTruncation: { [weak self] in
                guard let self, let payload = self.currentPayload, let callbacks = self.currentCallbacks else { return }
                callbacks.onExpandText(payload.post)
            }
        )

        let availableWidth = Self.availableContentWidth(
            totalWidth: payload.layoutWidth,
            depth: currentDepth,
            avatarSize: currentAvatarSize,
            avatarSpacing: currentAvatarSpacing
        )
        let renderSizes = payload.renderContent.segments.map { segment -> CGSize? in
            guard case .image(let image) = segment else {
                return nil
            }
            return FirePostCellLayoutCalculator.imageRenderSize(
                for: image,
                availableWidth: availableWidth,
                depth: currentDepth
            )
        }
        let nextSignature = payload.renderContent.segments.map(\.signatureToken)
        if contentSegmentSignature != nextSignature {
            rebuildContentSegmentNodes(payload.renderContent.segments, renderSizes: renderSizes)
            contentSegmentSignature = nextSignature
        } else {
            updateContentSegmentNodes(payload.renderContent.segments, renderSizes: renderSizes)
        }
    }

    private func configureImageOnlySegmentNodes(payload: FirePostCellRenderPayload) {
        let availableWidth = Self.availableContentWidth(
            totalWidth: payload.layoutWidth,
            depth: currentDepth,
            avatarSize: currentAvatarSize,
            avatarSpacing: currentAvatarSpacing
        )
        let imageSegments = payload.renderContent.segments.compactMap { segment -> FireTopicPostRenderSegment? in
            guard case .image = segment else { return nil }
            return segment
        }
        let renderSizes = imageSegments.map { segment -> CGSize? in
            guard case .image(let image) = segment else {
                return nil
            }
            return FirePostCellLayoutCalculator.imageRenderSize(
                for: image,
                availableWidth: availableWidth,
                depth: currentDepth
            )
        }
        let nextSignature = imageSegments.map(\.signatureToken)
        if contentSegmentSignature != nextSignature {
            rebuildContentSegmentNodes(imageSegments, renderSizes: renderSizes)
            contentSegmentSignature = nextSignature
        } else {
            updateContentSegmentNodes(imageSegments, renderSizes: renderSizes)
        }
    }

    private func configureBodyText(payload: FirePostCellRenderPayload) {
        guard let attrText = payload.renderContent.attributedText, attrText.length > 0 else {
            bodyTextNode.attributedText = nil
            bodyTextNode.isHidden = true
            bodySelectableTextNode.attributedText = nil
            bodySelectableTextNode.isHidden = true
            return
        }

        let contentID = "post:\(payload.post.id)|render:\(payload.renderContent.signature.token)"
        let isCollapsed = payload.textExpansionState.isCollapsed

        if renderedContentID != contentID {
            renderedContentID = contentID
            bodyTextNode.attributedText = attrText
            bodySelectableTextNode.attributedText = attrText
        }
        bodyTextNode.isHidden = !isCollapsed
        bodySelectableTextNode.isHidden = isCollapsed
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
        bodySelectableTextNode.onLink = { [weak self] url in
            self?.currentCallbacks?.onLinkTapped(url)
        }
    }

    private func rebuildContentSegmentNodes(
        _ segments: [FireTopicPostRenderSegment],
        renderSizes: [CGSize?]
    ) {
        for node in contentSegmentNodes {
            node.removeFromSupernode()
        }
        contentSegmentNodes.removeAll()
        contentSegmentSignature = segments.map(\.signatureToken)

        for (index, segment) in segments.enumerated() {
            switch segment {
            case .text(let attributedText):
                let textNode = FireSelectableRichTextNode()
                configureSelectableTextNode(textNode)
                textNode.attributedText = attributedText
                textNode.isHidden = false
                textNode.onLink = { [weak self] url in
                    self?.currentCallbacks?.onLinkTapped(url)
                }
                contentSegmentNodes.append(textNode)
            case .image(let image):
                let renderSize = index < renderSizes.count
                    ? (renderSizes[index] ?? CGSize(width: 1, height: 1))
                    : CGSize(width: 1, height: 1)
                let imageNode = FirePostImageNode(image: image, renderSize: renderSize)
                imageNode.onTap = { [weak self, weak imageNode] in
                    guard let imageNode else { return }
                    self?.handleImageTap(imageNode)
                }
                contentSegmentNodes.append(imageNode)
            }
        }
    }

    private func updateContentSegmentNodes(
        _ segments: [FireTopicPostRenderSegment],
        renderSizes: [CGSize?]
    ) {
        for (index, node) in contentSegmentNodes.enumerated() {
            guard index < segments.count else {
                break
            }
            switch (node, segments[index]) {
            case (let textNode as FireSelectableRichTextNode, .text(let attributedText)):
                textNode.attributedText = attributedText
                textNode.isHidden = false
                textNode.onLink = { [weak self] url in
                    self?.currentCallbacks?.onLinkTapped(url)
                }
            case (let imageNode as FirePostImageNode, .image):
                if index < renderSizes.count, let renderSize = renderSizes[index] {
                    imageNode.updateRenderSize(renderSize)
                }
            default:
                continue
            }
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
        let title: String
        if payload.isLoadingReplyContext {
            title = "正在加载回复..."
        } else if payload.replyContextError?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            title = "加载失败，点按重试"
        } else {
            title = count > 0 ? "查看更多 \(count) 条回复" : "查看更多回复"
        }
        replyShortcutNode.setAttributedTitle(NSAttributedString(
            string: title,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .caption1),
                .foregroundColor: payload.replyContextError == nil
                    ? Self.accentTextColor
                    : UIColor.systemRed,
            ]
        ), for: .normal)
        replyShortcutNode.accessibilityLabel = title
    }

    private func configureBoosts(payload: FirePostCellRenderPayload) {
        guard !payload.post.boosts.isEmpty else {
            boostContainerNode.isHidden = true
            boostBarrageNode.isHidden = true
            configureBoostBarrage(boosts: [], batchSignature: "")
            configureFixedBoostManualScroller(boosts: [])
            boostSignature = []
            return
        }

        let usesBodyBarrage = FirePostBoostDisplay.usesBodyBarrage(
            depth: currentDepth,
            textExpansionState: payload.textExpansionState,
            hasBodyTextTarget: payload.renderContent.hasBoostBarrageTextTarget
        )
        let bodyBarrageBoosts = usesBodyBarrage
            ? FirePostBoostDisplay.bodyBarrageBoosts(for: payload.post.boosts)
            : []
        boostBarrageNode.isHidden = !usesBodyBarrage || bodyBarrageBoosts.isEmpty
        configureBoostBarrage(
            boosts: bodyBarrageBoosts,
            batchSignature: usesBodyBarrage && !bodyBarrageBoosts.isEmpty
                ? FirePostBoostDisplay.bodyBarrageBatchSignature(
                    postID: payload.post.id,
                    boosts: payload.post.boosts
                )
                : ""
        )
        boostContainerNode.isHidden = usesBodyBarrage
        if usesBodyBarrage {
            configureFixedBoostManualScroller(boosts: [])
            boostSignature = []
            return
        }

        let nextSignature = payload.post.boosts.map { boost in
            [
                String(boost.id),
                boost.user.username,
                boost.user.name ?? "",
                boost.displayText,
                FirePostBoostDisplay.contentSignature(for: boost),
            ].joined(separator: "\u{1E}")
        }
        if boostSignature != nextSignature {
            boostSignature = nextSignature
        }
        configureFixedBoostManualScroller(boosts: payload.post.boosts)
        boostContainerNode.setNeedsLayout()
    }

    private func configureFixedBoostManualScroller(boosts: [TopicPostBoostState]) {
        boostManualBoosts = boosts
        boostManualScrollerNode.isHidden = boosts.isEmpty
        guard boostManualScrollerNode.isNodeLoaded,
              let view = boostManualScrollerNode.view as? FirePostBoostManualScrollerView else {
            return
        }
        view.configure(boosts: boosts)
    }

    private func configureBoostBarrage(boosts: [TopicPostBoostState], batchSignature: String) {
        boostBarrageBoosts = boosts
        boostBarrageLines = boosts.map(FirePostBoostDisplay.displayLine(for:))
        boostBarrageBatchSignature = batchSignature
        guard boostBarrageNode.isNodeLoaded,
              let view = boostBarrageNode.view as? FirePostBoostBarrageView else {
            return
        }
        view.configure(boosts: boosts, batchSignature: batchSignature, animationsEnabled: boostAnimationsEnabled)
    }

    func setBoostAnimationsEnabled(_ enabled: Bool) {
        guard boostAnimationsEnabled != enabled else { return }
        boostAnimationsEnabled = enabled
        if boostBarrageNode.isNodeLoaded,
           let view = boostBarrageNode.view as? FirePostBoostBarrageView {
            view.setAnimationsEnabled(enabled)
        }
    }

    private func configureReactions(payload: FirePostCellRenderPayload) {
        guard !payload.post.reactions.isEmpty else {
            reactionContainerNode.isHidden = true
            if !reactionButtons.isEmpty {
                rebuildReactionButtons([], payload: payload)
            }
            displayedReactions = []
            reactionButtonIDs = []
            reactionSignature = nil
            return
        }

        let visibleReactions = FirePostReactionDisplayPolicy.visibleReactions(
            from: payload.post.reactions,
            depth: currentDepth
        )
        guard !visibleReactions.isEmpty else {
            reactionContainerNode.isHidden = true
            if !reactionButtons.isEmpty {
                rebuildReactionButtons([], payload: payload)
            }
            displayedReactions = []
            reactionButtonIDs = []
            reactionSignature = nil
            return
        }

        reactionContainerNode.isHidden = false
        let nextSig = Self.reactionSignatureString(
            reactions: visibleReactions,
            currentUserReactionID: payload.post.currentUserReaction?.id,
            canWrite: payload.canWriteInteractions,
            isMutating: payload.isMutating
        )
        let nextIDs = visibleReactions.map(\.id)
        if reactionButtonIDs != nextIDs {
            rebuildReactionButtons(visibleReactions, payload: payload)
        } else if reactionSignature != nextSig {
            updateReactionButtons(visibleReactions, payload: payload)
        }
        displayedReactions = visibleReactions
        reactionButtonIDs = nextIDs
        reactionSignature = nextSig
    }

    private func rebuildReactionButtons(_ reactions: [TopicReactionState], payload: FirePostCellRenderPayload) {
        for button in reactionButtons {
            button.removeFromSupernode()
        }
        reactionButtons.removeAll()
        reactionButtonIDs = reactions.map(\.id)

        for reaction in reactions {
            let button = ASButtonNode()
            button.addTarget(self, action: #selector(handleReactionTap(_:)), forControlEvents: .touchUpInside)
            configureReactionButton(button, reaction: reaction, payload: payload)
            reactionButtons.append(button)
        }
    }

    private func updateReactionButtons(_ reactions: [TopicReactionState], payload: FirePostCellRenderPayload) {
        for (button, reaction) in zip(reactionButtons, reactions) {
            configureReactionButton(button, reaction: reaction, payload: payload)
        }
    }

    private func configureReactionButton(
        _ button: ASButtonNode,
        reaction: TopicReactionState,
        payload: FirePostCellRenderPayload
    ) {
        let canChangeReaction = payload.canWriteInteractions
            && !payload.isMutating
            && (payload.post.currentUserReaction?.canUndo ?? true)

        let option = FireTopicPresentation.reactionOption(for: reaction.id)
        let isMine = payload.post.currentUserReaction?.id == reaction.id
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
        button.borderWidth = isMine ? 1 : 0
        button.borderColor = isMine
            ? Self.accentTextColor.withAlphaComponent(0.85).cgColor
            : UIColor.clear.cgColor
        button.isEnabled = canChangeReaction
        button.accessibilityLabel = "\(option.label) \(reaction.count)"
        var traits: UIAccessibilityTraits = .button
        if isMine {
            traits.insert(.selected)
        }
        button.accessibilityTraits = traits
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
        let contentAvailableWidth = Self.availableContentWidth(
            totalWidth: totalWidth,
            depth: currentDepth,
            avatarSize: currentAvatarSize,
            avatarSpacing: currentAvatarSpacing
        )
        let shouldSuppressAttachments: Bool
        if let currentResolvedLayout {
            shouldSuppressAttachments = currentResolvedLayout.textExpansionFrame != nil
        } else {
            let hasImageSegments = currentPayload?.renderContent.segments.contains(where: \.isImage) ?? false
            shouldSuppressAttachments = (hasImageSegments || !pollContainerNode.isHidden)
                && Self.shouldSuppressAttachmentsForCollapsedText(
                    plainText: currentPayload?.renderContent.plainText ?? "",
                    hasAttributedText: currentPayload?.renderContent.attributedText != nil,
                    textExpansionState: currentPayload?.textExpansionState ?? .disabled,
                    totalWidth: totalWidth,
                    depth: currentDepth,
                    avatarSize: currentAvatarSize,
                    avatarSpacing: currentAvatarSpacing,
                    contentSizeCategory: currentContentSizeCategory
                )
        }

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
        var authorChildren: [ASLayoutElement] = [usernameNode]
        if !authorBadgeNode.isHidden {
            authorChildren.append(authorBadgeNode)
        }
        if !acceptedAnswerNode.isHidden {
            authorChildren.append(acceptedAnswerNode)
        }
        if !menuNode.isHidden {
            menuNode.style.preferredSize = CGSize(width: 20, height: 20)
            authorChildren.append(menuNode)
        }
        let authorRow = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 5,
            justifyContent: .start,
            alignItems: .center,
            children: authorChildren
        )
        authorRow.style.flexShrink = 1.0
        authorRow.style.flexGrow = 0.0

        let firstLineSpacer = ASLayoutSpec()
        firstLineSpacer.style.flexGrow = 1.0

        let metaChildren: [ASLayoutElement] = [authorRow, firstLineSpacer, timestampNode]
        let metaRow = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 6,
            justifyContent: .start,
            alignItems: .center,
            children: metaChildren
        )
        metaRow.style.flexShrink = 1.0

        // Content column
        var contentChildren: [ASLayoutElement] = [metaRow]
        var didAttachBoostBarrage = false
        var secondaryChildren: [ASLayoutElement] = []
        if !replyContextNode.isHidden {
            secondaryChildren.append(replyContextNode)
        }
        if !authorMetadataNode.isHidden {
            secondaryChildren.append(authorMetadataNode)
        }
        if !secondaryChildren.isEmpty {
            let secondarySpacer = ASLayoutSpec()
            secondarySpacer.style.flexGrow = 1.0
            secondaryChildren.append(secondarySpacer)
            secondaryChildren.append(postNumberNode)
            let secondaryRow = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: 6,
                justifyContent: .start,
                alignItems: .center,
                children: secondaryChildren
            )
            secondaryRow.style.flexShrink = 1.0
            contentChildren.append(secondaryRow)
        } else {
            let secondarySpacer = ASLayoutSpec()
            secondarySpacer.style.flexGrow = 1.0
            let postNumberRow = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: 0,
                justifyContent: .start,
                alignItems: .center,
                children: [secondarySpacer, postNumberNode]
            )
            contentChildren.append(postNumberRow)
        }

        if !bodyTextNode.isHidden {
            contentChildren.append(bodyElement(bodyTextNode, didAttachBoostBarrage: &didAttachBoostBarrage))
        }
        if !bodySelectableTextNode.isHidden {
            contentChildren.append(bodyElement(bodySelectableTextNode, didAttachBoostBarrage: &didAttachBoostBarrage))
        }

        if !shouldSuppressAttachments {
            for segmentNode in contentSegmentNodes {
                contentChildren.append(bodyElement(segmentNode, didAttachBoostBarrage: &didAttachBoostBarrage))
            }

            // Poll container
            if !pollContainerNode.isHidden {
                contentChildren.append(pollContainerNode)
            }

            if !boostContainerNode.isHidden {
                contentChildren.append(boostContainerNode)
            }
        }

        let reactionRow: ASStackLayoutSpec?
        if !reactionContainerNode.isHidden && !reactionButtons.isEmpty {
            let row = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: 8,
                justifyContent: .start,
                alignItems: .start,
                children: reactionButtons
            )
            if FirePostReactionDisplayPolicy.allowsWrapping(depth: currentDepth) {
                row.flexWrap = .wrap
                row.alignContent = .start
                row.style.flexGrow = 1.0
            }
            row.style.flexShrink = 1.0
            reactionRow = row
        } else {
            reactionRow = nil
        }

        var actionRowChildren: [ASLayoutElement] = []
        if !replyShortcutNode.isHidden {
            replyShortcutNode.style.flexGrow = 0
            replyShortcutNode.style.flexShrink = 1.0
            actionRowChildren.append(replyShortcutNode)
        }
        if let reactionRow {
            if !actionRowChildren.isEmpty {
                let actionSpacer = ASLayoutSpec()
                actionSpacer.style.flexGrow = 1.0
                actionRowChildren.append(actionSpacer)
            }
            actionRowChildren.append(reactionRow)
        }
        if FirePostReactionDisplayPolicy.allowsWrapping(depth: currentDepth),
           replyShortcutNode.isHidden,
           let reactionRow {
            reactionRow.style.minWidth = ASDimensionMake(max(contentAvailableWidth, 1))
            reactionRow.style.maxWidth = ASDimensionMake(max(contentAvailableWidth, 1))
            contentChildren.append(reactionRow)
        } else if !actionRowChildren.isEmpty {
            let actionRow = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: 8,
                justifyContent: .start,
                alignItems: .center,
                children: actionRowChildren
            )
            actionRow.style.flexShrink = 1.0
            actionRow.style.minHeight = ASDimensionMake(FirePostCellLayoutCalculator.replyShortcutHeight)
            contentChildren.append(actionRow)
        }

        // Divider
        if !dividerNode.isHidden {
            dividerNode.style.preferredSize = CGSize(width: max(contentAvailableWidth, 1), height: 0.5)
            contentChildren.append(dividerNode)
        }

        let contentStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 5,
            justifyContent: .start,
            alignItems: .stretch,
            children: contentChildren
        )
        contentStack.style.flexGrow = 1.0
        contentStack.style.flexShrink = 1.0
        contentStack.style.minWidth = ASDimensionMake(max(contentAvailableWidth, 1))
        contentStack.style.maxWidth = ASDimensionMake(max(contentAvailableWidth, 1))

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

    @objc private func handleProfileTap() {
        guard let username = currentPayload?.post.username.trimmingCharacters(in: .whitespacesAndNewlines),
              !username.isEmpty else {
            return
        }
        currentCallbacks?.onOpenProfile(username)
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
              index < displayedReactions.count else {
            return
        }
        let reaction = displayedReactions[index]
        if reaction.id == "heart" {
            callbacks.onToggleLike(payload.post)
        } else {
            callbacks.onSelectReaction(payload.post, reaction.id)
        }
    }

    // MARK: - Gesture Recognition

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === swipeGestureRecognizer,
              let panGesture = gestureRecognizer as? UIPanGestureRecognizer else {
            return true
        }

        let location = panGesture.location(in: view)
        guard canBeginReplySwipe(at: location) else {
            return false
        }

        let translation = panGesture.translation(in: view)
        let velocity = panGesture.velocity(in: view)
        let horizontalMovement = max(abs(translation.x), abs(velocity.x))
        let verticalMovement = max(abs(translation.y), abs(velocity.y))

        return translation.x > 0
            && velocity.x >= 0
            && horizontalMovement > verticalMovement * 1.15
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard gestureRecognizer === swipeGestureRecognizer else {
            return true
        }
        return canBeginReplySwipe(at: touch.location(in: view))
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === swipeGestureRecognizer || otherGestureRecognizer === swipeGestureRecognizer
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

    private static func badgeAttributedText(parts: [String]) -> NSAttributedString {
        let captionFont = UIFont.preferredFont(forTextStyle: .caption2)
        let result = NSMutableAttributedString()
        let colors: [UIColor] = [
            UIColor.systemOrange,
            UIColor.systemTeal,
            UIColor.systemIndigo,
            UIColor.systemPink,
        ]
        for (index, part) in parts.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: " "))
            }
            let color = colors[index % colors.count]
            result.append(NSAttributedString(
                string: part,
                attributes: [
                    .font: UIFontMetrics(forTextStyle: .caption2).scaledFont(
                        for: UIFont.systemFont(ofSize: captionFont.pointSize, weight: .semibold)
                    ),
                    .foregroundColor: color,
                    .backgroundColor: color.withAlphaComponent(0.13),
                ]
            ))
        }
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

    private static func reactionSignatureString(
        reactions: [TopicReactionState],
        currentUserReactionID: String?,
        canWrite: Bool,
        isMutating: Bool
    ) -> String {
        let reactionTokens = reactions.map { reaction in
            [reaction.id, String(reaction.count), String(reaction.canUndo ?? true)].joined(separator: ":")
        }.joined(separator: "|")
        return [
            reactionTokens,
            currentUserReactionID ?? "",
            String(canWrite),
            String(isMutating),
        ].joined(separator: "\u{1F}")
    }

    private func bodyElement(
        _ node: ASDisplayNode,
        didAttachBoostBarrage: inout Bool
    ) -> ASLayoutElement {
        guard !boostBarrageNode.isHidden,
              !didAttachBoostBarrage,
              node is ASTextNode || node is FireSelectableRichTextNode else {
            return node
        }
        didAttachBoostBarrage = true
        boostBarrageNode.style.flexGrow = 1.0
        boostBarrageNode.style.flexShrink = 1.0
        return ASOverlayLayoutSpec(
            child: node,
            overlay: boostBarrageNode
        )
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

    private func configureSelectableTextNode(_ node: FireSelectableRichTextNode) {
        node.isHidden = true
        node.style.flexShrink = 1.0
    }

    private func replySwipeActivationRect() -> CGRect {
        if let layout = currentResolvedLayout {
            let visibleFrames = [
                layout.metaFrame,
                layout.textFrame,
                layout.replyShortcutFrame,
                layout.reactionsFrame,
            ].compactMap { $0 } + layout.imageFrames + layout.pollFrames + layout.boostFrames
            let union = visibleFrames.reduce(CGRect.null) { partial, frame in
                partial.union(frame)
            }
            if !union.isNull {
                return union.insetBy(dx: 0, dy: -8)
            }
        }

        let indent = FirePostCellLayoutCalculator.indentWidth(for: currentDepth)
        let leading = FirePostCellLayoutCalculator.outerHorizontalPadding
            + indent
            + currentAvatarSize
            + currentAvatarSpacing
        return CGRect(
            x: leading,
            y: 0,
            width: max(view.bounds.width - leading - FirePostCellLayoutCalculator.outerHorizontalPadding, 1),
            height: view.bounds.height
        )
    }

    private func canBeginReplySwipe(at location: CGPoint) -> Bool {
        if location.x <= 44 {
            return false
        }
        guard replySwipeActivationRect().contains(location) else {
            return false
        }
        return !isTouchInsideInteractiveContent(at: location)
    }

    private func isTouchInsideInteractiveContent(at location: CGPoint) -> Bool {
        guard let hitView = view.hitTest(location, with: nil) else {
            return false
        }
        if hitView.isDescendant(ofType: UITextView.self) {
            return true
        }
        if hitView.isDescendant(ofType: UIControl.self) {
            return true
        }
        for node in contentSegmentNodes where node is FirePostImageNode {
            let frame = node.view.convert(node.view.bounds, to: view)
            if frame.contains(location) {
                return true
            }
        }
        return false
    }

    static func shouldSuppressAttachmentsForCollapsedText(
        plainText: String,
        hasAttributedText: Bool,
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
        guard let textHeight = FirePostCellLayoutCalculator.estimatedRichTextHeight(
            plainText: plainText,
            hasAttributedText: hasAttributedText,
            containerWidth: availableWidth,
            contentSizeCategory: contentSizeCategory,
            textExpansionState: textExpansionState
        ) else {
            return false
        }
        return textHeight > FirePostCellLayoutCalculator.collapsedTextHeight(
            contentSizeCategory: contentSizeCategory
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
        shouldSuppressAttachmentsForCollapsedText(
            plainText: attributedText?.string ?? "",
            hasAttributedText: attributedText != nil,
            textExpansionState: textExpansionState,
            totalWidth: totalWidth,
            depth: depth,
            avatarSize: avatarSize,
            avatarSpacing: avatarSpacing,
            contentSizeCategory: contentSizeCategory
        )
    }

    private func showLoadedAvatar() {
        avatarNode.alpha = 1
    }

    private func showAvatarFallback() {
        avatarNode.alpha = 0
    }

    private func cancelAvatarLoad() {
        avatarLoadTask?.cancel()
        avatarLoadTask = nil
        avatarLoadGeneration &+= 1
        avatarNode.image = nil
        showAvatarFallback()
    }

    private func loadAvatar(url: URL) {
        avatarLoadTask?.cancel()
        avatarLoadGeneration &+= 1
        let generation = avatarLoadGeneration
        let request = FireRemoteImageRequest(url: url)

        if let cachedImage = FireRemoteImagePipeline.shared.cachedImage(for: request) {
            avatarNode.image = cachedImage
            showLoadedAvatar()
            return
        }

        avatarNode.image = nil
        showAvatarFallback()
        avatarLoadTask = Task { [weak self] in
            do {
                let image = try await FireRemoteImagePipeline.shared.loadImage(for: request)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.applyLoadedAvatar(image, generation: generation)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.applyFailedAvatarLoad(generation: generation)
                }
            }
        }
    }

    private func applyLoadedAvatar(_ image: UIImage, generation: UInt64) {
        guard generation == avatarLoadGeneration else { return }
        avatarNode.image = image
        showLoadedAvatar()
    }

    private func applyFailedAvatarLoad(generation: UInt64) {
        guard generation == avatarLoadGeneration else { return }
        avatarNode.image = nil
        showAvatarFallback()
    }

    deinit {
        avatarLoadTask?.cancel()
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

private final class FireSelectableRichTextNode: ASDisplayNode, UITextViewDelegate {
    var attributedText: NSAttributedString? {
        didSet {
            applyText()
            setNeedsLayout()
        }
    }

    var onLink: ((URL) -> Void)?
    private var richTextView: UITextView?

    override init() {
        super.init()
        isUserInteractionEnabled = true
        style.flexShrink = 1.0
    }

    override func didLoad() {
        super.didLoad()
        let textView = FireRichTextTextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.adjustsFontForContentSizeCategory = true
        textView.dataDetectorTypes = []
        textView.delegate = self
        textView.frame = bounds
        textView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(textView)
        richTextView = textView
        applyText()
    }

    override func layout() {
        super.layout()
        richTextView?.frame = bounds
    }

    override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        guard let attributedText, attributedText.length > 0 else {
            return .zero
        }
        let width = max(constrainedSize.width, 1)
        let bounds = attributedText.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return CGSize(width: width, height: max(ceil(bounds.height), 1))
    }

    func textView(
        _ textView: UITextView,
        shouldInteractWith URL: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        onLink?(URL)
        return false
    }

    func textView(
        _ textView: UITextView,
        shouldInteractWith URL: URL,
        in characterRange: NSRange
    ) -> Bool {
        onLink?(URL)
        return false
    }

    private func applyText() {
        guard isNodeLoaded else {
            return
        }
        richTextView?.attributedText = attributedText
        (richTextView as? FireRichTextTextView)?.refreshQuotePreviewLayers()
    }
}

private extension UIView {
    func isDescendant<T: UIView>(ofType type: T.Type) -> Bool {
        var current: UIView? = self
        while let view = current {
            if view is T {
                return true
            }
            current = view.superview
        }
        return false
    }
}

private final class FirePostImageNode: ASControlNode {
    let image: FireCookedImage
    var onTap: (() -> Void)?
    private let imageNode = ASImageNode()
    private let statusNode = ASTextNode()
    private let retryNode = ASButtonNode()
    private var renderSize: CGSize
    private var loadTask: Task<Void, Never>?
    private var loadGeneration: UInt64 = 0
    private var isLoaded = false
    private var isLoading = false
    private var didFail = false
    private lazy var tapGestureRecognizer: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
        gesture.cancelsTouchesInView = false
        return gesture
    }()

    init(image: FireCookedImage, renderSize: CGSize) {
        self.image = image
        self.renderSize = renderSize
        super.init()
        automaticallyManagesSubnodes = true
        isUserInteractionEnabled = true
        accessibilityLabel = image.altText?.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty("帖子图片")
        accessibilityTraits = [.image, .button]

        imageNode.contentMode = .scaleAspectFit
        imageNode.clipsToBounds = true
        imageNode.cornerRadius = 16
        imageNode.borderColor = UIColor.separator.cgColor
        imageNode.borderWidth = 0.5
        imageNode.backgroundColor = .tertiarySystemFill
        imageNode.isUserInteractionEnabled = false
        imageNode.displaysAsynchronously = true

        statusNode.maximumNumberOfLines = 2
        statusNode.isLayerBacked = true

        retryNode.setAttributedTitle(NSAttributedString(
            string: "重试",
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .caption1),
                .foregroundColor: UIColor.systemBlue,
            ]
        ), for: .normal)
        retryNode.contentEdgeInsets = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        retryNode.cornerRadius = 12
        retryNode.borderWidth = 1
        retryNode.borderColor = UIColor.systemBlue.withAlphaComponent(0.45).cgColor
        retryNode.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.8)
        retryNode.addTarget(self, action: #selector(handleRetryTap), forControlEvents: .touchUpInside)

        updateRenderSize(renderSize)
        loadImage()
    }

    override func didLoad() {
        super.didLoad()
        view.addGestureRecognizer(tapGestureRecognizer)
    }

    deinit {
        loadTask?.cancel()
    }

    func updateRenderSize(_ renderSize: CGSize) {
        let didChange = self.renderSize != renderSize
        self.renderSize = renderSize
        style.preferredSize = renderSize
        imageNode.style.preferredSize = renderSize
        if didChange {
            if isLoaded {
                loadImage()
            }
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
        guard !isLoaded else {
            return ASWrapperLayoutSpec(layoutElement: imageNode)
        }

        statusNode.attributedText = statusAttributedText()
        retryNode.isHidden = !didFail

        let statusChildren: [ASLayoutElement] = didFail ? [statusNode, retryNode] : [statusNode]
        let statusStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 8,
            justifyContent: .center,
            alignItems: .center,
            children: statusChildren
        )
        statusStack.style.maxWidth = ASDimensionMake(max(boundedSize.width - 24, 1))

        let centeredStatus = ASCenterLayoutSpec(
            centeringOptions: .XY,
            sizingOptions: [],
            child: statusStack
        )
        centeredStatus.style.preferredSize = boundedSize

        return ASOverlayLayoutSpec(child: imageNode, overlay: centeredStatus)
    }

    private func loadImage() {
        loadTask?.cancel()
        loadGeneration &+= 1
        let generation = loadGeneration
        let request = FireTopicImageRequestBuilder.cookedImageRequest(image)

        if let cachedImage = FireRemoteImagePipeline.shared.cachedImage(for: request) {
            applyLoadedImage(cachedImage, generation: generation)
            return
        }

        isLoaded = false
        isLoading = true
        didFail = false
        imageNode.image = nil
        setNeedsLayout()

        loadTask = Task { [weak self] in
            do {
                let resolvedImage = try await FireRemoteImagePipeline.shared.loadImage(for: request)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.applyLoadedImage(resolvedImage, generation: generation)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.applyFailedLoad(generation: generation)
                }
            }
        }
    }

    private func applyLoadedImage(_ loadedImage: UIImage, generation: UInt64) {
        guard generation == loadGeneration else { return }
        imageNode.image = thumbnailImage(for: loadedImage)
        isLoaded = true
        isLoading = false
        didFail = false
        setNeedsLayout()
    }

    private func applyFailedLoad(generation: UInt64) {
        guard generation == loadGeneration else { return }
        isLoaded = false
        isLoading = false
        didFail = true
        imageNode.image = nil
        setNeedsLayout()
    }

    @objc private func handleRetryTap() {
        loadImage()
    }

    @objc private func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
        guard gestureRecognizer.state == .ended, !didFail else {
            return
        }
        onTap?()
    }

    private func statusAttributedText() -> NSAttributedString {
        let text = didFail ? "图片加载失败" : "图片加载中..."
        return NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .caption1),
                .foregroundColor: UIColor.secondaryLabel,
            ]
        )
    }

    private func thumbnailImage(for image: UIImage) -> UIImage {
        let scale = UIScreen.main.scale
        let targetSize = CGSize(
            width: max(renderSize.width * scale, 1),
            height: max(renderSize.height * scale, 1)
        )
        return image.preparingThumbnail(of: targetSize)
            ?? image.preparingForDisplay()
            ?? image
    }
}

// MARK: - Boost Animation Helpers

private enum FirePostBoostLayerAnimator {
    static func pause(_ layers: [CALayer]) {
        for layer in layers where layer.speed != 0 {
            let pausedTime = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0
            layer.timeOffset = pausedTime
        }
    }

    static func resume(_ layers: [CALayer]) {
        for layer in layers where layer.speed == 0 {
            let pausedTime = layer.timeOffset
            layer.speed = 1
            layer.timeOffset = 0
            layer.beginTime = 0
            let elapsed = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
            layer.beginTime = elapsed
        }
    }

    static func hasPausedAnimation(_ layers: [CALayer]) -> Bool {
        layers.contains { $0.speed == 0 }
    }

    static func hasAnimation(_ layers: [CALayer]) -> Bool {
        layers.contains { !($0.animationKeys() ?? []).isEmpty }
    }

    static func resetTiming(_ layers: [CALayer]) {
        for layer in layers {
            layer.speed = 1
            layer.timeOffset = 0
            layer.beginTime = 0
        }
    }

    static func stableHash(text: String?, index: Int) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in (text ?? "").utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        hash ^= UInt32(index & 0xFFFF)
        return hash
    }
}

// MARK: - Boost Barrage

private final class FirePostBoostBarrageView: UIView {
    private static let maximumLaneCount = 5
    private static let chipHeight: CGFloat = 24
    private static let minimumLaneGap: CGFloat = 4
    private static var displayedBatchSignatures: Set<String> = []

    private var chips: [FirePostBoostChipView] = []
    private var signature: String = ""
    private var batchSignature: String = ""
    private var lastAnimatedBounds: CGRect = .null
    private var animationsEnabled = true
    private var animationRunID: UInt64 = 0
    private var pendingAnimationCompletionCount = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(boosts: [TopicPostBoostState], batchSignature: String, animationsEnabled: Bool) {
        let visibleBoosts = boosts.filter {
            !$0.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let isCurrentActiveBatch = batchSignature == self.batchSignature && !chips.isEmpty
        guard !batchSignature.isEmpty,
              !Self.displayedBatchSignatures.contains(batchSignature) || isCurrentActiveBatch else {
            signature = ""
            self.batchSignature = batchSignature
            removeAllLabels()
            isHidden = true
            return
        }
        let nextSignature = visibleBoosts.map(FirePostBoostDisplay.contentSignature(for:)).joined(separator: "\u{1E}")
        guard nextSignature != signature || batchSignature != self.batchSignature else {
            isHidden = visibleBoosts.isEmpty
            setAnimationsEnabled(animationsEnabled)
            return
        }

        self.animationsEnabled = animationsEnabled
        signature = nextSignature
        self.batchSignature = batchSignature
        chips.forEach { chip in
            chip.layer.removeAllAnimations()
            chip.removeFromSuperview()
        }
        chips.removeAll()
        isHidden = visibleBoosts.isEmpty

        for boost in visibleBoosts {
            let chip = FirePostBoostChipView(
                backgroundColor: UIColor.systemBackground.withAlphaComponent(0.72),
                textColor: .label,
                borderColor: UIColor.systemOrange.withAlphaComponent(0.28)
            )
            chip.configure(
                attributedText: FirePostBoostDisplay.displayContent(
                    for: boost,
                    textColor: .label,
                    accentColor: .systemBlue
                ),
                signature: FirePostBoostDisplay.contentSignature(for: boost)
            )
            addSubview(chip)
            chips.append(chip)
        }
        restartLayoutAndAnimations()
    }

    func setAnimationsEnabled(_ enabled: Bool) {
        guard animationsEnabled != enabled else { return }
        animationsEnabled = enabled
        if enabled {
            let layers = chips.map(\.layer)
            if FirePostBoostLayerAnimator.hasPausedAnimation(layers),
               FirePostBoostLayerAnimator.hasAnimation(layers) {
                FirePostBoostLayerAnimator.resume(layers)
            } else if !FirePostBoostLayerAnimator.hasAnimation(layers) {
                FirePostBoostLayerAnimator.resetTiming(layers)
                restartLayoutAndAnimations()
            }
        } else {
            FirePostBoostLayerAnimator.pause(chips.map(\.layer))
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutLabelsAndStartAnimationIfNeeded()
    }

    private func layoutLabelsAndStartAnimationIfNeeded() {
        guard !chips.isEmpty,
              bounds.width > 1,
              bounds.height > 1,
              lastAnimatedBounds != bounds else {
            return
        }
        lastAnimatedBounds = bounds

        let availableLaneCount = max(
            1,
            min(
                Self.maximumLaneCount,
                Int((bounds.height + Self.minimumLaneGap) / (Self.chipHeight + Self.minimumLaneGap))
            )
        )
        let laneCount = max(1, min(chips.count, availableLaneCount))
        let maxChipWidth = max(bounds.width * 0.72, 1)
        let shouldAnimate = animationsEnabled && !UIAccessibility.isReduceMotionEnabled
        let laneStep = laneCount > 1
            ? max((bounds.height - Self.chipHeight) / CGFloat(laneCount - 1), Self.minimumLaneGap)
            : 0
        let runID: UInt64
        if shouldAnimate {
            animationRunID &+= 1
            runID = animationRunID
            pendingAnimationCompletionCount = chips.count
            Self.displayedBatchSignatures.insert(batchSignature)
        } else {
            runID = animationRunID
            pendingAnimationCompletionCount = 0
        }

        for (index, chip) in chips.enumerated() {
            chip.layer.removeAllAnimations()
            chip.transform = .identity
            let measured = chip.sizeThatFits(CGSize(width: maxChipWidth, height: Self.chipHeight))
            let chipWidth = min(max(measured.width, 48), maxChipWidth)
            let lane = index % laneCount
            let laneCycle = index / laneCount
            let hash = FirePostBoostLayerAnimator.stableHash(text: chip.signature, index: index)
            let jitterLimit = laneCount > 1 ? min(laneStep * 0.18, 4) : 0
            let jitter = jitterLimit > 0
                ? (CGFloat(Int(hash % 100)) / 99 - 0.5) * jitterLimit
                : 0
            let y = min(
                max(CGFloat(lane) * laneStep + jitter, 0),
                max(bounds.height - Self.chipHeight, 0)
            )
            let startOffset = CGFloat(hash % 42)
            let startX = bounds.width
                + startOffset
                + CGFloat(laneCycle) * (bounds.width * 0.22 + 56)
            chip.frame = CGRect(
                x: shouldAnimate ? startX : staticX(for: index, width: chipWidth),
                y: y,
                width: chipWidth,
                height: Self.chipHeight
            )
            chip.alpha = 0.92

            guard shouldAnimate else { continue }
            let travel = startX + chipWidth + 24
            let durationJitter = Double((hash >> 8) % 90) / 100
            let delayJitter = Double((hash >> 16) % 45) / 100
            UIView.animate(
                withDuration: 9.4 + durationJitter + Double(laneCycle) * 0.35,
                delay: Double(index) * 0.48 + delayJitter,
                options: [.curveLinear, .allowUserInteraction],
                animations: {
                    chip.transform = CGAffineTransform(translationX: -travel, y: 0)
                    chip.alpha = 0.62
                },
                completion: { [weak self] finished in
                    self?.recordAnimationCompletion(runID: runID, finished: finished)
                }
            )
        }
    }

    private func staticX(for index: Int, width: CGFloat) -> CGFloat {
        let slotCount = max(chips.count + 1, 2)
        let progress = CGFloat(index + 1) / CGFloat(slotCount)
        return max((bounds.width - width) * progress, 0)
    }

    private func restartLayoutAndAnimations() {
        lastAnimatedBounds = .null
        FirePostBoostLayerAnimator.resetTiming(chips.map(\.layer))
        animationRunID &+= 1
        pendingAnimationCompletionCount = 0
        chips.forEach { chip in
            chip.layer.removeAllAnimations()
            chip.transform = .identity
        }
        setNeedsLayout()
    }

    private func removeAllLabels() {
        animationRunID &+= 1
        pendingAnimationCompletionCount = 0
        chips.forEach { chip in
            chip.layer.removeAllAnimations()
            chip.removeFromSuperview()
        }
        chips.removeAll()
        lastAnimatedBounds = .null
    }

    private func recordAnimationCompletion(runID: UInt64, finished: Bool) {
        guard finished,
              runID == animationRunID,
              pendingAnimationCompletionCount > 0 else {
            return
        }
        pendingAnimationCompletionCount -= 1
        guard pendingAnimationCompletionCount == 0,
              !batchSignature.isEmpty else {
            return
        }
        removeAllLabels()
        signature = ""
        isHidden = true
    }
}

private final class FirePostBoostChipView: UIView {
    private(set) var signature: String = ""
    private let textView = FireRichTextUIView()
    private let horizontalInset: CGFloat = 10

    init(backgroundColor: UIColor, textColor: UIColor, borderColor: UIColor? = nil) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        clipsToBounds = true
        self.backgroundColor = backgroundColor
        layer.cornerRadius = 12
        layer.masksToBounds = true
        if let borderColor {
            layer.borderWidth = 0.5
            layer.borderColor = borderColor.cgColor
        }
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = false
        textView.isUserInteractionEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.backgroundColor = .clear
        textView.textColor = textColor
        textView.textContainer.maximumNumberOfLines = 1
        textView.textContainer.lineBreakMode = .byTruncatingTail
        addSubview(textView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(attributedText: NSAttributedString, signature: String) {
        self.signature = signature
        textView.renderedContentID = "boost:\(signature)"
        textView.attributedText = attributedText
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        textView.frame = bounds.insetBy(dx: horizontalInset, dy: 0)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let textSize = textView.sizeThatFits(CGSize(
            width: max(size.width - horizontalInset * 2, 1),
            height: size.height
        ))
        return CGSize(
            width: min(textSize.width + horizontalInset * 2, size.width),
            height: size.height
        )
    }
}

// MARK: - Fixed Boost Manual Scroller

private final class FirePostBoostManualScrollerView: UIView {
    private static let laneCount = 2
    private static let chipHeight: CGFloat = 22

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private var rowViews: [UIView] = []
    private var chips: [FirePostBoostChipView] = []
    private var signature: String = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        clipsToBounds = false
        backgroundColor = .clear
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = false
        scrollView.delaysContentTouches = false
        scrollView.backgroundColor = .clear
        addSubview(scrollView)
        scrollView.addSubview(contentView)
        for _ in 0..<Self.laneCount {
            let row = UIView()
            row.clipsToBounds = false
            contentView.addSubview(row)
            rowViews.append(row)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(boosts: [TopicPostBoostState]) {
        let visibleBoosts = boosts.filter {
            !$0.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let nextSignature = visibleBoosts.map(FirePostBoostDisplay.contentSignature(for:)).joined(separator: "\u{1E}")
        guard nextSignature != signature else {
            isHidden = visibleBoosts.isEmpty
            return
        }

        signature = nextSignature
        chips.forEach { chip in
            chip.removeFromSuperview()
        }
        chips.removeAll()
        scrollView.setContentOffset(.zero, animated: false)
        isHidden = visibleBoosts.isEmpty

        for (index, boost) in visibleBoosts.enumerated() {
            let chip = FirePostBoostChipView(
                backgroundColor: UIColor.secondarySystemFill.withAlphaComponent(0.78),
                textColor: .secondaryLabel
            )
            chip.configure(
                attributedText: FirePostBoostDisplay.displayContent(
                    for: boost,
                    textColor: .secondaryLabel,
                    accentColor: .systemBlue
                ),
                signature: FirePostBoostDisplay.contentSignature(for: boost)
            )
            rowViews[index % Self.laneCount].addSubview(chip)
            chips.append(chip)
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutRows()
    }

    private func layoutRows() {
        guard bounds.width > 1, bounds.height > 1 else {
            return
        }

        let rowHeight = FirePostCellLayoutCalculator.fixedBoostManualRowHeight
        let rowSpacing = FirePostCellLayoutCalculator.fixedBoostManualRowSpacing
        scrollView.frame = bounds
        let maxChipWidth = max(bounds.width * 0.72, 1)
        var cursorXByRow = Array(repeating: CGFloat(0), count: Self.laneCount)
        for (index, chip) in chips.enumerated() {
            let rowIndex = index % Self.laneCount
            let measured = chip.sizeThatFits(CGSize(width: maxChipWidth, height: Self.chipHeight))
            let chipWidth = min(max(measured.width, 48), maxChipWidth)
            chip.frame = CGRect(
                x: cursorXByRow[rowIndex],
                y: max((rowHeight - Self.chipHeight) / 2, 0),
                width: chipWidth,
                height: Self.chipHeight
            )
            chip.alpha = 1
            chip.transform = .identity
            cursorXByRow[rowIndex] += chipWidth + 8
        }

        let contentWidth = max((cursorXByRow.max() ?? 0) - 8, bounds.width)
        contentView.frame = CGRect(x: 0, y: 0, width: contentWidth, height: bounds.height)
        scrollView.contentSize = CGSize(width: contentWidth, height: bounds.height)
        for (rowIndex, row) in rowViews.enumerated() {
            row.transform = .identity
            row.frame = CGRect(
                x: 0,
                y: CGFloat(rowIndex) * (rowHeight + rowSpacing),
                width: contentWidth,
                height: rowHeight
            )
        }
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
