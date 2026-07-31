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
    /// Idle reaction chips stay nearly transparent — avoid muddy tertiary fills.
    private static let reactionIdleFillColor = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(white: 1.0, alpha: 0.06)
        }
        return UIColor.clear
    }
    private static let reactionIdleBorderColor = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(white: 1.0, alpha: 0.12)
        }
        return UIColor(white: 0.0, alpha: 0.08)
    }
    private static let reactionIdleLabelColor = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(white: 0.78, alpha: 1)
        }
        return UIColor(white: 0.36, alpha: 1)
    }
    private static let reactionMineFillColor = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.96, green: 0.45, blue: 0.22, alpha: 0.18)
        }
        return UIColor(red: 0.91, green: 0.39, blue: 0.18, alpha: 0.10)
    }
    private static let reactionMineBorderColor = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.96, green: 0.45, blue: 0.22, alpha: 0.55)
        }
        return UIColor(red: 0.91, green: 0.39, blue: 0.18, alpha: 0.45)
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
    private let replyShortcutNode = ASButtonNode()
    /// Always-visible primary actions + overflow for secondary tools.
    private let actionReplyNode = ASButtonNode()
    private let actionReactNode = ASButtonNode()
    private let actionBoostNode = ASButtonNode()
    private let overflowNode = ASButtonNode()
    private let actionQuoteNode = ASButtonNode()
    private let actionBookmarkNode = ASButtonNode()
    private let actionEditNode = ASButtonNode()
    private let actionFlagNode = ASButtonNode()
    private let reactionPickerScrollNode = FireInlineReactionPickerScrollNode()
    private var reactionPickerButtons: [ASButtonNode] = []
    private var reactionPickerOptionIDs: [String] = []
    private var areOverflowActionsExpanded = false
    private var overflowCollapseWorkItem: DispatchWorkItem?
    private lazy var swipeReplyRevealLabel: UILabel = {
        let label = UILabel()
        label.text = "回复"
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = Self.accentTextColor
        label.alpha = 0
        label.isHidden = true
        return label
    }()
    private lazy var boostBarrageNode: ASDisplayNode = {
        let node = ASDisplayNode(viewBlock: {
            FirePostBoostBarrageView()
        })
        node.onDidLoad { [weak self] node in
            guard let view = node.view as? FirePostBoostBarrageView else { return }
            view.configure(
                boosts: self?.boostBarrageBoosts ?? [],
                batchSignature: self?.boostBarrageBatchSignature ?? "",
                animationsEnabled: self?.boostAnimationsEnabled ?? true,
                baseURLString: self?.currentPayload?.baseURLString ?? "https://linux.do"
            )
        }
        return node
    }()
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
    /// Captured on main in `didLoad`; safe for Texture background configure paths.
    private var cachedDisplayScale: CGFloat = 3
    private static var lastKnownContentSizeCategory: UIContentSizeCategory = .large
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
                boosts: self?.boostManualBoosts ?? [],
                baseURLString: self?.currentPayload?.baseURLString ?? "https://linux.do"
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
        cachedDisplayScale = UIScreen.main.scale
        Self.lastKnownContentSizeCategory = UIApplication.shared.preferredContentSizeCategory
        currentContentSizeCategory = Self.lastKnownContentSizeCategory
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
        backgroundColor = FireTheme.uiCanvas

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
        replyContextNode.fireBindPressBounce(.compact)
        replyContextNode.isHidden = true
        replyContextNode.style.flexShrink = 1.0

        timestampNode.isLayerBacked = true
        acceptedAnswerNode.isHidden = true
        acceptedAnswerNode.isLayerBacked = true
        postNumberNode.isLayerBacked = true

        menuNode.isHidden = true
        menuNode.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        menuNode.addTarget(self, action: #selector(handleMenuTap), forControlEvents: .touchUpInside)
        menuNode.fireBindPressBounce(.compact)
        menuNode.accessibilityLabel = "帖子操作"

        // Body text
        configureRichTextNode(bodyTextNode)
        configureSelectableTextNode(bodySelectableTextNode)

        // Images
        imageContainerNode.isHidden = true

        // Polls — host UIKit poll controls; keep interaction on so options receive taps.
        pollContainerNode.isHidden = true
        pollContainerNode.isUserInteractionEnabled = true
        pollContainerNode.clipsToBounds = false

        // Boosts
        boostContainerNode.isHidden = true
        boostContainerNode.automaticallyManagesSubnodes = true
        boostContainerNode.layoutSpecBlock = { [weak self] _, _ in
            guard let self, !self.boostManualScrollerNode.isHidden else { return ASLayoutSpec() }
            let availableWidth = max(
                Self.availableContentWidth(
                    totalWidth: self.currentLayoutWidth,
                    depth: self.currentDepth,
                    avatarSize: self.currentAvatarSize,
                    avatarSpacing: self.currentAvatarSpacing
                ),
                1
            )
            let scrollerSize = CGSize(
                width: availableWidth,
                height: self.fixedBoostManualScrollerHeight(availableWidth: availableWidth)
            )
            self.boostManualScrollerNode.style.preferredSize = scrollerSize
            self.boostManualScrollerNode.style.minHeight = ASDimensionMake(scrollerSize.height)
            self.boostManualScrollerNode.style.maxHeight = ASDimensionMake(scrollerSize.height)
            return ASWrapperLayoutSpec(layoutElement: self.boostManualScrollerNode)
        }
        boostContainerNode.isUserInteractionEnabled = true
        boostManualScrollerNode.isHidden = true
        boostManualScrollerNode.isUserInteractionEnabled = true
        boostBarrageNode.isHidden = true
        boostBarrageNode.isUserInteractionEnabled = false

        // Reply-thread bubble (home-list style) — expand / collapse nested replies.
        replyShortcutNode.isHidden = true
        replyShortcutNode.addTarget(self, action: #selector(handleReplyShortcutTap), forControlEvents: .touchUpInside)
        replyShortcutNode.fireBindPressBounce(.compact)
        replyShortcutNode.accessibilityLabel = "展开回复"

        // Primary: reply / react / boost stay visible. Overflow expands secondary tools.
        configureActionIcon(actionReplyNode, systemName: "arrowshape.turn.up.left", accessibilityLabel: "回复")
        actionReplyNode.addTarget(self, action: #selector(handleActionReplyTap), forControlEvents: .touchUpInside)
        configureActionIcon(actionReactNode, systemName: "face.smiling", accessibilityLabel: "回应")
        actionReactNode.addTarget(self, action: #selector(handleActionReactTap), forControlEvents: .touchUpInside)
        configureActionIcon(actionBoostNode, systemName: "bolt", accessibilityLabel: "Boost")
        actionBoostNode.addTarget(self, action: #selector(handleActionBoostTap), forControlEvents: .touchUpInside)
        configureActionIcon(overflowNode, systemName: "ellipsis.circle", accessibilityLabel: "更多操作")
        overflowNode.addTarget(self, action: #selector(handleOverflowTap), forControlEvents: .touchUpInside)
        configureActionIcon(actionQuoteNode, systemName: "text.quote", accessibilityLabel: "引用回复")
        actionQuoteNode.addTarget(self, action: #selector(handleActionQuoteTap), forControlEvents: .touchUpInside)
        configureActionIcon(actionBookmarkNode, systemName: "bookmark", accessibilityLabel: "书签")
        actionBookmarkNode.addTarget(self, action: #selector(handleActionBookmarkTap), forControlEvents: .touchUpInside)
        configureActionIcon(actionEditNode, systemName: "pencil", accessibilityLabel: "编辑")
        actionEditNode.addTarget(self, action: #selector(handleActionEditTap), forControlEvents: .touchUpInside)
        configureActionIcon(actionFlagNode, systemName: "flag", accessibilityLabel: "举报")
        actionFlagNode.addTarget(self, action: #selector(handleActionFlagTap), forControlEvents: .touchUpInside)

        // Reactions — keep bounce overshoot visible at the container level.
        // Never touch `.view` here: setupNodes runs inside Texture node-blocks off-main.
        reactionContainerNode.isHidden = true
        reactionContainerNode.clipsToBounds = false
        reactionPickerScrollNode.isHidden = true

        // Divider
        dividerNode.backgroundColor = .separator
        dividerNode.isHidden = true
    }

    /// Texture may call configure/setup from a background node-block queue.
    /// UIView/CALayer access must hop to main; node properties stay thread-safe.
    private func performOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
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
        // UIApplication is main-thread only; node-blocks may configure off-main.
        if Thread.isMainThread {
            Self.lastKnownContentSizeCategory = UIApplication.shared.preferredContentSizeCategory
            cachedDisplayScale = UIScreen.main.scale
        }
        currentContentSizeCategory = Self.lastKnownContentSizeCategory

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
        // Reset per-row overflow expansion on reuse / reconfigure.
        // UIView transform / label work must stay on main — configure may run in a
        // Texture background node-block.
        cancelOverflowAutoCollapse()
        areOverflowActionsExpanded = false
        resetSwipeReplyReveal(animated: false)

        configureReplyShortcut(payload: payload)
        configureOverflowActions(payload: payload)
        configureReactionPicker(payload: payload)
        configureReactions(payload: payload)
        configureSearchHighlight(payload.isSearchHighlighted)
        configureDivider(shows: showsDivider)
    }

    private func configureSearchHighlight(_ isHighlighted: Bool) {
        backgroundColor = isHighlighted
            ? Self.accentTextColor.withAlphaComponent(0.10)
            : FireTheme.uiCanvas
        borderWidth = isHighlighted ? 1 : 0
        borderColor = isHighlighted
            ? Self.accentTextColor.withAlphaComponent(0.70).cgColor
            : UIColor.clear.cgColor
        cornerRadius = isHighlighted ? 8 : 0
        clipsToBounds = isHighlighted
    }

    private func configureAvatar(payload: FirePostCellRenderPayload, avatarSize: CGFloat) {
        let username = payload.post.username.isEmpty ? "?" : payload.post.username
        let avatarURL = fireAvatarURL(
            avatarTemplate: payload.post.avatarTemplate,
            size: avatarSize,
            scale: cachedDisplayScale,
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
            // Caption weight keeps "回复 @user" secondary to the display name on the same row.
            let replyContextFont = UIFont.preferredFont(forTextStyle: .caption1)
            replyContextNode.setAttributedTitle(NSAttributedString(
                string: replyContext,
                attributes: [.font: replyContextFont, .foregroundColor: Self.accentTextColor]
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

        // Header `...` is retired — overflow lives in the bottom action strip.
        menuNode.isHidden = true
        menuNode.isEnabled = false
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
            renderedContentID = nil
            return
        }

        let isCollapsed = payload.textExpansionState.isCollapsed
        // Include collapse state so ASTextNode rebuilds when expanding/collapsing
        // (blank-line normalization only applies while collapsed).
        let contentID = "post:\(payload.post.id)|render:\(payload.renderContent.signature.token)|collapsed:\(isCollapsed)"

        if renderedContentID != contentID {
            renderedContentID = contentID
            let collapsedDisplay = FirePostCollapsedTextNormalizer.attributedTextForCollapsedDisplay(attrText)
            // Clear first so Texture invalidates cached text layout (intermittent stale metrics).
            bodyTextNode.attributedText = nil
            bodyTextNode.attributedText = isCollapsed ? collapsedDisplay : attrText
            bodySelectableTextNode.attributedText = attrText
        }
        bodyTextNode.isHidden = !isCollapsed
        bodySelectableTextNode.isHidden = isCollapsed
        bodyTextNode.maximumNumberOfLines = isCollapsed
            ? UInt(FirePostTextExpansionState.collapsedLineLimit)
            : 0
        bodyTextNode.truncationAttributedText = isCollapsed
            ? FirePostCollapsedTextNormalizer.expansionTruncationToken(accentColor: Self.accentTextColor)
            : nil
        // Keep natural height tight to measured glyphs — do not let the stack stretch lines.
        bodyTextNode.style.flexGrow = 0
        bodyTextNode.style.flexShrink = 1.0
        bodySelectableTextNode.style.flexGrow = 0

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
        } else {
            updatePollInteractionState(payload: payload)
        }
    }

    private func updatePollInteractionState(payload: FirePostCellRenderPayload) {
        let canWrite = payload.canWriteInteractions
        let isMutating = payload.isMutating
        performOnMain { [weak self] in
            guard let self else { return }
            for view in self.pollViews {
                view.updateInteractionState(canInteract: canWrite, isMutating: isMutating)
            }
        }
    }

    private func rebuildPollViews(
        _ polls: [PollState],
        _ models: [FirePostPollRenderModel],
        payload: FirePostCellRenderPayload,
        availableWidth: CGFloat? = nil
    ) {
        // Do not touch UIView hierarchy here — this path can run off-main in Texture.
        pollHeights.removeAll(keepingCapacity: true)
        let width = availableWidth ?? Self.availableContentWidth(
            totalWidth: payload.layoutWidth,
            depth: currentDepth,
            avatarSize: currentAvatarSize,
            avatarSpacing: currentAvatarSpacing
        )

        // Heights are pure layout math and can stay on the Texture worker queue.
        var nextHeights: [CGFloat] = []
        nextHeights.reserveCapacity(models.count)
        for model in models {
            nextHeights.append(FirePostPollView.preferredHeight(
                for: model,
                availableWidth: width,
                contentSizeCategory: currentContentSizeCategory
            ))
        }
        pollHeights = nextHeights
        let totalPollHeight = pollHeights.reduce(0, +) + CGFloat(max(pollHeights.count - 1, 0)) * 10
        // Width must match the laid-out poll views. A 1pt container still draws subviews
        // that overflow its bounds, but UIKit hit-testing never reaches those controls.
        pollContainerNode.style.preferredSize = CGSize(width: max(width, 1), height: ceil(totalPollHeight))
        pollContainerNode.style.minWidth = ASDimensionMake(max(width, 1))
        pollContainerNode.style.maxWidth = ASDimensionMake(max(width, 1))

        // UIView construction / hierarchy edits must happen on main.
        let pollsSnapshot = polls
        let modelsSnapshot = models
        let canWrite = payload.canWriteInteractions
        let isMutating = payload.isMutating
        performOnMain { [weak self] in
            guard let self else { return }
            for view in self.pollViews {
                view.removeFromSuperview()
            }
            self.pollViews.removeAll(keepingCapacity: true)

            for (index, model) in modelsSnapshot.enumerated() {
                guard index < pollsSnapshot.count else { break }
                let pollView = FirePostPollView()
                let poll = pollsSnapshot[index]
                pollView.isUserInteractionEnabled = true
                pollView.configure(
                    model: model,
                    canInteract: canWrite,
                    isMutating: isMutating,
                    onSubmit: { [weak self] selectedOptions in
                        guard let self,
                              let p = self.currentPayload,
                              let callbacks = self.currentCallbacks else { return }
                        callbacks.onVotePoll(p.post, poll, selectedOptions)
                    },
                    onRemoveVote: { [weak self] in
                        guard let self,
                              let p = self.currentPayload,
                              let callbacks = self.currentCallbacks else { return }
                        callbacks.onUnvotePoll(p.post, poll)
                    }
                )
                self.pollContainerNode.view.addSubview(pollView)
                self.pollViews.append(pollView)
            }
            self.setNeedsLayout()
        }
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
        let baseURLString = currentPayload?.baseURLString ?? "https://linux.do"
        performOnMain { [weak self] in
            guard let self,
                  self.boostManualScrollerNode.isNodeLoaded,
                  let view = self.boostManualScrollerNode.view as? FirePostBoostManualScrollerView else {
                return
            }
            view.configure(boosts: boosts, baseURLString: baseURLString)
        }
    }

    private func fixedBoostManualScrollerHeight(availableWidth: CGFloat) -> CGFloat {
        guard let payload = currentPayload else {
            return FirePostCellLayoutCalculator.fixedBoostManualHeight(forUsedRowCount: 1)
        }
        let boostLines = FirePostBoostDisplay.fixedDisplayLines(
            for: boostManualBoosts,
            depth: currentDepth,
            textExpansionState: payload.textExpansionState,
            hasBodyTextTarget: payload.renderContent.hasBoostBarrageTextTarget
        )
        return FirePostCellLayoutCalculator.fixedBoostManualHeight(
            boostLines: boostLines,
            containerWidth: availableWidth,
            contentSizeCategory: currentContentSizeCategory
        )
    }

    private func configureBoostBarrage(boosts: [TopicPostBoostState], batchSignature: String) {
        boostBarrageBoosts = boosts
        boostBarrageLines = boosts.map(FirePostBoostDisplay.displayLine(for:))
        boostBarrageBatchSignature = batchSignature
        let animationsEnabled = boostAnimationsEnabled
        let baseURLString = currentPayload?.baseURLString ?? "https://linux.do"
        performOnMain { [weak self] in
            guard let self,
                  self.boostBarrageNode.isNodeLoaded,
                  let view = self.boostBarrageNode.view as? FirePostBoostBarrageView else {
                return
            }
            view.configure(
                boosts: boosts,
                batchSignature: batchSignature,
                animationsEnabled: animationsEnabled,
                baseURLString: baseURLString
            )
        }
    }

    private func configureReplyShortcut(payload: FirePostCellRenderPayload) {
        guard let count = payload.replyShortcutCount else {
            replyShortcutNode.isHidden = true
            replyShortcutNode.setImage(nil, for: .normal)
            replyShortcutNode.setAttributedTitle(nil, for: .normal)
            return
        }
        replyShortcutNode.isHidden = false
        // Always tappable so expand/collapse is never blocked by a loading flag.
        replyShortcutNode.isEnabled = true

        let expanded = payload.isReplyThreadExpanded
        let symbolName = expanded ? "bubble.left.fill" : "bubble.left"
        // Collapsed = muted; expanded thread = accent orange for icon AND count.
        let tint = expanded ? Self.accentTextColor : Self.tertiaryInkColor
        // Same glyph size as reply/react/boost action icons (14pt medium).
        let symbolConfig = UIImage.SymbolConfiguration(
            pointSize: 14,
            weight: expanded ? .semibold : .medium
        )
        // Template + tintColor keeps SF Symbol color in sync with the count label
        // (alwaysOriginal dynamic UIColor can leave the glyph on the stale muted tint).
        if let image = UIImage(systemName: symbolName, withConfiguration: symbolConfig) {
            replyShortcutNode.tintColor = tint
            replyShortcutNode.imageNode.tintColor = tint
            replyShortcutNode.setImage(image.withRenderingMode(.alwaysTemplate), for: .normal)
            replyShortcutNode.setImage(image.withRenderingMode(.alwaysTemplate), for: .disabled)
            replyShortcutNode.setImage(image.withRenderingMode(.alwaysTemplate), for: .highlighted)
        }
        replyShortcutNode.imageNode.contentMode = .center

        let countText = payload.isLoadingReplyContext ? "…" : "\(count)"
        let countFont = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .systemFont(ofSize: 13, weight: expanded ? .semibold : .medium)
        )
        let countAttributes: [NSAttributedString.Key: Any] = [
            .font: countFont,
            .foregroundColor: tint,
        ]
        replyShortcutNode.setAttributedTitle(NSAttributedString(
            string: countText,
            attributes: countAttributes
        ), for: .normal)
        replyShortcutNode.setAttributedTitle(NSAttributedString(
            string: countText,
            attributes: countAttributes
        ), for: .disabled)
        replyShortcutNode.setAttributedTitle(NSAttributedString(
            string: countText,
            attributes: countAttributes
        ), for: .highlighted)
        replyShortcutNode.contentSpacing = 4
        replyShortcutNode.contentHorizontalAlignment = .middle
        replyShortcutNode.contentVerticalAlignment = .center
        // Match action-icon hit box height; width fits icon + count.
        replyShortcutNode.style.minHeight = ASDimensionMake(
            FirePostCellLayoutCalculator.replyShortcutHeight
        )
        replyShortcutNode.style.minWidth = ASDimensionMake(
            FirePostCellLayoutCalculator.replyShortcutMinWidth
        )
        replyShortcutNode.hitTestSlop = UIEdgeInsets(top: -6, left: -6, bottom: -6, right: -6)
        replyShortcutNode.accessibilityLabel = expanded
            ? "收起 \(count) 条回复"
            : "展开 \(count) 条回复"
    }

    private func configureOverflowActions(payload: FirePostCellRenderPayload) {
        let canWrite = payload.canWriteInteractions && !payload.post.hidden
        let isMutating = payload.isMutating
        let showsChrome = payload.showsInlineActions
        let canBoost = canWrite && payload.post.canBoost
        let hasSecondary = canWrite
            || payload.post.canEdit
            || payload.post.canRecover
            || (payload.post.canDelete && !payload.post.hidden)

        // Primary actions stay visible so reply/react/boost are not buried under `...`.
        setActionVisible(actionReplyNode, visible: showsChrome && canWrite, enabled: canWrite && !isMutating)
        setActionVisible(actionReactNode, visible: showsChrome && canWrite, enabled: canWrite && !isMutating)
        setActionVisible(actionBoostNode, visible: showsChrome && canBoost, enabled: canBoost && !isMutating)
        applyActionSymbol(actionBoostNode, systemName: "bolt", highlighted: false)

        let showsOverflow = showsChrome && hasSecondary
        overflowNode.isHidden = !showsOverflow
        overflowNode.isEnabled = showsOverflow && !isMutating
        applyActionSymbol(
            actionReactNode,
            systemName: "face.smiling",
            highlighted: payload.isReactionPickerExpanded
        )
        applyActionSymbol(overflowNode, systemName: "ellipsis.circle", highlighted: areOverflowActionsExpanded)

        let expanded = showsOverflow && areOverflowActionsExpanded

        setActionVisible(actionQuoteNode, visible: expanded && canWrite, enabled: canWrite && !isMutating)

        let bookmarked = payload.post.bookmarked
        applyActionSymbol(
            actionBookmarkNode,
            systemName: bookmarked ? "bookmark.fill" : "bookmark",
            highlighted: bookmarked
        )
        actionBookmarkNode.accessibilityLabel = bookmarked ? "编辑书签" : "添加书签"
        setActionVisible(actionBookmarkNode, visible: expanded && canWrite, enabled: canWrite && !isMutating)

        setActionVisible(
            actionEditNode,
            visible: expanded && payload.post.canEdit,
            enabled: payload.post.canEdit && !isMutating
        )
        setActionVisible(
            actionFlagNode,
            visible: expanded && canWrite,
            enabled: canWrite && !isMutating
        )
    }

    private func configureActionIcon(
        _ button: ASButtonNode,
        systemName: String,
        accessibilityLabel: String
    ) {
        button.isHidden = true
        button.accessibilityLabel = accessibilityLabel
        button.fireBindPressBounce(.compact)
        button.contentHorizontalAlignment = .middle
        button.contentVerticalAlignment = .center
        applyActionSymbol(button, systemName: systemName, highlighted: false)
        let side = FirePostCellLayoutCalculator.actionIconSize
        button.style.preferredSize = CGSize(width: side, height: side)
    }

    private func applyActionSymbol(
        _ button: ASButtonNode,
        systemName: String,
        highlighted: Bool
    ) {
        let tint = highlighted ? Self.accentTextColor : Self.tertiaryInkColor
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        if let image = UIImage(systemName: systemName, withConfiguration: config)?
            .withTintColor(tint, renderingMode: .alwaysOriginal) {
            button.setImage(image, for: .normal)
        }
        button.imageNode.contentMode = .center
    }

    private func setActionVisible(_ button: ASButtonNode, visible: Bool, enabled: Bool) {
        button.isHidden = !visible
        button.isEnabled = enabled
        button.alpha = enabled ? 1 : 0.45
    }

    func setBoostAnimationsEnabled(_ enabled: Bool) {
        guard boostAnimationsEnabled != enabled else { return }
        boostAnimationsEnabled = enabled
        performOnMain { [weak self] in
            guard let self,
                  self.boostBarrageNode.isNodeLoaded,
                  let view = self.boostBarrageNode.view as? FirePostBoostBarrageView else {
                return
            }
            view.setAnimationsEnabled(enabled)
        }
    }

    private func configureReactionPicker(payload: FirePostCellRenderPayload) {
        let options = payload.quickReactionOptions
        let expanded = payload.isReactionPickerExpanded
            && payload.canWriteInteractions
            && !payload.post.hidden
            && !options.isEmpty

        guard expanded else {
            reactionPickerScrollNode.isHidden = true
            reactionPickerScrollNode.buttons = []
            if !reactionPickerButtons.isEmpty {
                reactionPickerButtons.removeAll()
                reactionPickerOptionIDs = []
            }
            return
        }

        reactionPickerScrollNode.isHidden = false
        let nextIDs = options.map(\.id)
        if reactionPickerOptionIDs != nextIDs {
            reactionPickerButtons.removeAll()
            reactionPickerOptionIDs = nextIDs
            for option in options {
                let button = ASButtonNode()
                button.fireBindPressBounce(.chip)
                button.accessibilityLabel = option.label
                button.addTarget(self, action: #selector(handleQuickReactionTap(_:)), forControlEvents: .touchUpInside)
                reactionPickerButtons.append(button)
            }
        }

        let buttonSize = FirePostCellLayoutCalculator.reactionPickerButtonSize
        for (button, option) in zip(reactionPickerButtons, options) {
            let selected = payload.post.currentUserReaction?.id
                .caseInsensitiveCompare(option.id) == .orderedSame
            let title = NSAttributedString(
                string: option.symbol,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 20),
                ]
            )
            button.setAttributedTitle(title, for: .normal)
            button.backgroundColor = selected
                ? Self.accentTextColor.withAlphaComponent(0.16)
                : Self.reactionIdleFillColor
            button.borderColor = (selected ? Self.accentTextColor : Self.reactionIdleBorderColor).cgColor
            button.borderWidth = FirePostCellLayoutCalculator.reactionChipBorderWidth
            button.cornerRadius = buttonSize.height / 2
            button.contentEdgeInsets = .zero
            button.isEnabled = payload.canWriteInteractions
                && (payload.post.currentUserReaction?.canUndo ?? true)
            button.style.preferredSize = buttonSize
            button.style.flexGrow = 0
            button.style.flexShrink = 0
        }

        reactionPickerScrollNode.buttons = reactionPickerButtons
        reactionPickerScrollNode.style.preferredSize = CGSize(
            width: max(payload.layoutWidth - FirePostCellLayoutCalculator.outerHorizontalPadding * 2, 1),
            height: FirePostCellLayoutCalculator.reactionPickerStripHeight
        )
        reactionPickerScrollNode.setNeedsLayout()
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
            button.fireBindPressBounce(.chip)
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
        // Stay tappable while network is in-flight — optimistic UI owns the wait.
        // Only block when the user cannot write or the current reaction is locked.
        let canChangeReaction = payload.canWriteInteractions
            && (payload.post.currentUserReaction?.canUndo ?? true)

        let option = FireTopicPresentation.reactionOption(for: reaction.id)
        let isMine = payload.post.currentUserReaction?.id == reaction.id
        let symbolString = option.symbol
        let countString = "\(reaction.count)"
        // Fixed optical sizes keep emoji pills compact; Dynamic Type still scales count slightly.
        let emojiFont = UIFont.systemFont(
            ofSize: FirePostCellLayoutCalculator.reactionEmojiFontSize,
            weight: .regular
        )
        let countFont = UIFontMetrics(forTextStyle: .caption2).scaledFont(
            for: UIFont.monospacedDigitSystemFont(
                ofSize: FirePostCellLayoutCalculator.reactionCountFontSize,
                weight: isMine ? .semibold : .medium
            )
        )
        // Emoji keep full color; only the count follows selected/idle chrome.
        let countColor = isMine ? Self.accentTextColor : Self.reactionIdleLabelColor
        // Hair space keeps emoji|count tight without looking glued.
        let title = NSMutableAttributedString(
            string: "\(symbolString)\u{200A}",
            attributes: [.font: emojiFont, .foregroundColor: UIColor.label]
        )
        title.append(NSAttributedString(
            string: countString,
            attributes: [.font: countFont, .foregroundColor: countColor]
        ))
        button.setAttributedTitle(title, for: .normal)
        // Node-level chrome only — never touch `.view`/`.layer` here (node-block thread).
        button.cornerRadius = FirePostCellLayoutCalculator.reactionChipCornerRadius
        button.clipsToBounds = true
        button.contentEdgeInsets = FirePostCellLayoutCalculator.reactionChipContentInsets
        // Idle: no gray slab in light mode; faint glass edge in dark mode.
        // Mine: soft accent wash + border (readable on both themes).
        button.backgroundColor = isMine ? Self.reactionMineFillColor : Self.reactionIdleFillColor
        button.borderWidth = FirePostCellLayoutCalculator.reactionChipBorderWidth
        button.borderColor = (isMine ? Self.reactionMineBorderColor : Self.reactionIdleBorderColor).cgColor
        button.isEnabled = canChangeReaction
        button.accessibilityLabel = "\(option.label) \(reaction.count)"
        var traits: UIAccessibilityTraits = .button
        if isMine {
            traits.insert(.selected)
        }
        button.accessibilityTraits = traits
        // Prefer intrinsic compact size; avoid stretching in the action row.
        button.style.flexShrink = 0
        button.style.flexGrow = 0
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
        let outerPadding = FirePostCellLayoutCalculator.outerHorizontalPadding
        let totalWidth = constrainedSize.max.width.isFinite ? constrainedSize.max.width : currentLayoutWidth
        let rowAvailableWidth = max(totalWidth - outerPadding * 2 - indent, 1)
        let bodyAvailableWidth = Self.availableContentWidth(
            totalWidth: totalWidth,
            depth: currentDepth,
            avatarSize: currentAvatarSize,
            avatarSpacing: currentAvatarSpacing
        )
        let headerAvailableWidth = max(rowAvailableWidth - avatarSz - avatarSp, 1)
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
        let avatarColumn = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 0,
            justifyContent: .start,
            alignItems: .center,
            children: [avatarContainerNode, threadLineNode].filter { !$0.isHidden }
        )
        avatarColumn.style.minWidth = ASDimensionMake(avatarSz)
        avatarColumn.style.maxWidth = ASDimensionMake(avatarSz)
        avatarColumn.style.flexShrink = 0.0

        // Meta row: display name + "回复 @user" share the first line; @handle/tags stay below.
        var authorChildren: [ASLayoutElement] = [usernameNode]
        if !replyContextNode.isHidden {
            replyContextNode.style.flexShrink = 1.0
            authorChildren.append(replyContextNode)
        }
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

        // Header stays to the right of the avatar; body content uses the full row width below it.
        var headerChildren: [ASLayoutElement] = [metaRow]
        var didAttachBoostBarrage = false
        var secondaryChildren: [ASLayoutElement] = []
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
            headerChildren.append(secondaryRow)
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
            headerChildren.append(postNumberRow)
        }

        let headerContentStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: FirePostCellLayoutCalculator.headerStackSpacing,
            justifyContent: .start,
            alignItems: .stretch,
            children: headerChildren
        )
        headerContentStack.style.flexGrow = 1.0
        headerContentStack.style.flexShrink = 1.0
        headerContentStack.style.minWidth = ASDimensionMake(headerAvailableWidth)
        headerContentStack.style.maxWidth = ASDimensionMake(headerAvailableWidth)

        var bodyChildren: [ASLayoutElement] = []

        if !bodyTextNode.isHidden {
            bodyChildren.append(bodyElement(bodyTextNode, didAttachBoostBarrage: &didAttachBoostBarrage))
        }
        if !bodySelectableTextNode.isHidden {
            bodyChildren.append(bodyElement(bodySelectableTextNode, didAttachBoostBarrage: &didAttachBoostBarrage))
        }

        if !shouldSuppressAttachments {
            for segmentNode in contentSegmentNodes {
                bodyChildren.append(bodyElement(segmentNode, didAttachBoostBarrage: &didAttachBoostBarrage))
            }

            // Poll container
            if !pollContainerNode.isHidden {
                bodyChildren.append(pollContainerNode)
            }
        }

        // Footer chrome:
        // [bubble?] [reply react boost ...]
        // [quick reaction strip when expanded]
        // [existing reaction chips full width]
        var actionRowChildren: [ASLayoutElement] = []
        if !replyShortcutNode.isHidden {
            replyShortcutNode.style.flexGrow = 0
            replyShortcutNode.style.flexShrink = 0
            actionRowChildren.append(replyShortcutNode)
        }

        let primaryCluster = [
            actionReplyNode,
            actionReactNode,
            actionBoostNode,
            overflowNode,
        ].filter { !$0.isHidden }
        for node in primaryCluster {
            node.style.flexGrow = 0
            node.style.flexShrink = 0
            actionRowChildren.append(node)
        }

        let overflowCluster = [
            actionQuoteNode,
            actionBookmarkNode,
            actionFlagNode,
            actionEditNode,
        ].filter { !$0.isHidden }
        actionRowChildren.append(contentsOf: overflowCluster)

        var footerChildren: [ASLayoutElement] = []
        if !actionRowChildren.isEmpty {
            let actionRow = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: FirePostCellLayoutCalculator.actionIconSpacing,
                justifyContent: .start,
                alignItems: .center,
                children: actionRowChildren
            )
            actionRow.style.flexShrink = 1.0
            actionRow.style.minHeight = ASDimensionMake(FirePostCellLayoutCalculator.actionRowHeight)
            footerChildren.append(actionRow)
        }

        if !reactionPickerScrollNode.isHidden, !reactionPickerButtons.isEmpty {
            reactionPickerScrollNode.style.flexGrow = 1
            reactionPickerScrollNode.style.flexShrink = 1
            reactionPickerScrollNode.style.minHeight = ASDimensionMake(
                FirePostCellLayoutCalculator.reactionPickerStripHeight
            )
            reactionPickerScrollNode.style.maxHeight = ASDimensionMake(
                FirePostCellLayoutCalculator.reactionPickerStripHeight
            )
            footerChildren.append(reactionPickerScrollNode)
        }

        if !reactionContainerNode.isHidden, !reactionButtons.isEmpty {
            let reactionRow = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: FirePostCellLayoutCalculator.reactionChipHorizontalSpacing,
                justifyContent: .start,
                alignItems: .center,
                children: reactionButtons
            )
            reactionRow.style.flexShrink = 1.0
            reactionRow.style.minHeight = ASDimensionMake(
                FirePostCellLayoutCalculator.reactionChipHeight
            )
            footerChildren.append(reactionRow)
        }

        let actionElement: ASLayoutElement?
        if footerChildren.isEmpty {
            actionElement = nil
        } else if footerChildren.count == 1 {
            actionElement = footerChildren[0]
        } else {
            let stack = ASStackLayoutSpec(
                direction: .vertical,
                spacing: FirePostCellLayoutCalculator.reactionTopSpacing,
                justifyContent: .start,
                alignItems: .stretch,
                children: footerChildren
            )
            actionElement = stack
        }

        let boostElement: ASLayoutElement? = !shouldSuppressAttachments && !boostContainerNode.isHidden
            ? boostContainerNode
            : nil
        if let boostElement, let actionElement {
            let footerStack = ASStackLayoutSpec(
                direction: .vertical,
                spacing: 0,
                justifyContent: .start,
                alignItems: .stretch,
                children: [boostElement, actionElement]
            )
            footerStack.style.flexShrink = 1.0
            bodyChildren.append(footerStack)
        } else if let boostElement {
            bodyChildren.append(boostElement)
        } else if let actionElement {
            bodyChildren.append(actionElement)
        }

        // Divider
        if !dividerNode.isHidden {
            dividerNode.style.preferredSize = CGSize(width: max(bodyAvailableWidth, 1), height: 0.5)
            bodyChildren.append(dividerNode)
        }

        let rootStack: ASLayoutSpec
        if FirePostCellLayoutCalculator.usesFullWidthBody(for: currentDepth) {
            let headerRow = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: avatarSp,
                justifyContent: .start,
                alignItems: .start,
                children: [avatarColumn, headerContentStack]
            )
            headerRow.style.flexShrink = 1.0

            let contentChildren: [ASLayoutElement] = [headerRow] + bodyChildren
            let contentStack = ASStackLayoutSpec(
                direction: .vertical,
                spacing: FirePostCellLayoutCalculator.headerToBodySpacing,
                justifyContent: .start,
                alignItems: .stretch,
                children: contentChildren
            )
            contentStack.style.flexGrow = 1.0
            contentStack.style.flexShrink = 1.0
            contentStack.style.minWidth = ASDimensionMake(max(rowAvailableWidth, 1))
            contentStack.style.maxWidth = ASDimensionMake(max(rowAvailableWidth, 1))
            rootStack = contentStack
        } else {
            let contentColumnChildren: [ASLayoutElement] = [headerContentStack] + bodyChildren
            let contentColumn = ASStackLayoutSpec(
                direction: .vertical,
                spacing: FirePostCellLayoutCalculator.headerToBodySpacing,
                justifyContent: .start,
                alignItems: .stretch,
                children: contentColumnChildren
            )
            contentColumn.style.flexGrow = 1.0
            contentColumn.style.flexShrink = 1.0
            contentColumn.style.minWidth = ASDimensionMake(max(bodyAvailableWidth, 1))
            contentColumn.style.maxWidth = ASDimensionMake(max(bodyAvailableWidth, 1))

            let row = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: avatarSp,
                justifyContent: .start,
                alignItems: .stretch,
                children: [avatarColumn, contentColumn]
            )
            row.style.flexShrink = 1.0
            row.style.minWidth = ASDimensionMake(max(rowAvailableWidth, 1))
            row.style.maxWidth = ASDimensionMake(max(rowAvailableWidth, 1))
            rootStack = row
        }

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

        // Size poll views inside the container. Prefer the container's laid-out width so
        // hit targets match the Texture frame (do not overflow a narrow parent bounds).
        let fallbackWidth = Self.availableContentWidth(
            totalWidth: calculatedSize.width,
            depth: currentDepth,
            avatarSize: currentAvatarSize,
            avatarSpacing: currentAvatarSpacing
        )
        let containerWidth = pollContainerNode.bounds.width
        let availableWidth = containerWidth > 1 ? containerWidth : fallbackWidth

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

    @objc private func handleOverflowTap() {
        guard currentPayload?.showsInlineActions == true else { return }
        if areOverflowActionsExpanded {
            setOverflowActionsExpanded(false, animated: true)
        } else {
            setOverflowActionsExpanded(true, animated: true)
            scheduleOverflowAutoCollapse()
        }
    }

    @objc private func handleActionReplyTap() {
        guard let payload = currentPayload, let callbacks = currentCallbacks else { return }
        FireMotionHaptics.impact(.light)
        callbacks.onReplyPost(payload.post)
    }

    @objc private func handleActionReactTap() {
        guard let payload = currentPayload, let callbacks = currentCallbacks else { return }
        FireMotionHaptics.impact(.light)
        callbacks.onToggleReactionPicker(payload.post)
    }

    @objc private func handleQuickReactionTap(_ sender: ASButtonNode) {
        guard let payload = currentPayload,
              let callbacks = currentCallbacks,
              let index = reactionPickerButtons.firstIndex(where: { $0 === sender }),
              index < payload.quickReactionOptions.count else {
            return
        }
        let option = payload.quickReactionOptions[index]
        FireMotionHaptics.selection()
        callbacks.onSelectReaction(payload.post, option.id)
    }

    @objc private func handleActionBoostTap() {
        guard let payload = currentPayload, let callbacks = currentCallbacks else { return }
        FireMotionHaptics.impact(.light)
        callbacks.onBoostPost(payload.post)
    }

    @objc private func handleActionQuoteTap() {
        guard let payload = currentPayload, let callbacks = currentCallbacks else { return }
        noteOverflowInteraction()
        FireMotionHaptics.impact(.light)
        callbacks.onQuotePost(payload.post)
        setOverflowActionsExpanded(false, animated: true)
    }

    @objc private func handleActionBookmarkTap() {
        guard let payload = currentPayload, let callbacks = currentCallbacks else { return }
        noteOverflowInteraction()
        FireMotionHaptics.impact(.light)
        callbacks.onBookmarkPost(payload.post)
        setOverflowActionsExpanded(false, animated: true)
    }

    @objc private func handleActionEditTap() {
        guard let payload = currentPayload, let callbacks = currentCallbacks else { return }
        noteOverflowInteraction()
        callbacks.onEditPost(payload.post)
        setOverflowActionsExpanded(false, animated: true)
    }

    @objc private func handleActionFlagTap() {
        guard let payload = currentPayload, let callbacks = currentCallbacks else { return }
        noteOverflowInteraction()
        callbacks.onFlagPost(payload.post)
        setOverflowActionsExpanded(false, animated: true)
    }

    @objc private func handleReplyShortcutTap() {
        guard let payload = currentPayload,
              let callbacks = currentCallbacks else {
            return
        }
        // Toggle must work even while nested replies are still loading.
        FireMotionHaptics.impact(.light)
        callbacks.onOpenReplies(payload.post)
    }

    private func setOverflowActionsExpanded(_ expanded: Bool, animated: Bool) {
        guard areOverflowActionsExpanded != expanded else {
            if expanded { scheduleOverflowAutoCollapse() }
            return
        }
        areOverflowActionsExpanded = expanded
        if !expanded {
            cancelOverflowAutoCollapse()
        }

        let overflowActionNodes = [
            actionQuoteNode,
            actionBookmarkNode,
            actionFlagNode,
            actionEditNode,
        ]

        let applyConfig = { [weak self] in
            guard let self, let payload = self.currentPayload else { return }
            self.configureOverflowActions(payload: payload)
        }

        let runUpdates = { [weak self] in
            guard let self else { return }
            if !animated {
                applyConfig()
                self.setNeedsLayout()
                if self.isNodeLoaded {
                    self.layoutIfNeeded()
                }
                if expanded {
                    self.scheduleOverflowAutoCollapse()
                }
                return
            }

            // Match the top toolbar: width/presence settles first, then a short horizontal
            // fade — never animate Texture layout from a zero frame (that flies from top-left).
            if expanded {
                applyConfig()
                UIView.performWithoutAnimation {
                    self.setNeedsLayout()
                    if self.isNodeLoaded {
                        self.layoutIfNeeded()
                    }
                    for node in overflowActionNodes where !node.isHidden {
                        // Accessing `.view` forces load so first expand can animate.
                        node.alpha = 0
                        node.view.transform = CGAffineTransform(translationX: -10, y: 0)
                    }
                }
                UIView.animate(
                    withDuration: 0.24,
                    delay: 0,
                    usingSpringWithDamping: 0.88,
                    initialSpringVelocity: 0.25,
                    options: [.allowUserInteraction, .beginFromCurrentState]
                ) {
                    for node in overflowActionNodes where !node.isHidden {
                        node.alpha = 1
                        node.view.transform = .identity
                    }
                }
                self.scheduleOverflowAutoCollapse()
                return
            }

            let visibleNodes = overflowActionNodes.filter { !$0.isHidden }
            UIView.animate(
                withDuration: 0.18,
                delay: 0,
                options: [.curveEaseIn, .beginFromCurrentState, .allowUserInteraction],
                animations: {
                    for node in visibleNodes {
                        node.alpha = 0
                        node.view.transform = CGAffineTransform(translationX: -8, y: 0)
                    }
                },
                completion: { _ in
                    for node in visibleNodes {
                        node.view.transform = .identity
                        node.alpha = 1
                    }
                    applyConfig()
                    self.setNeedsLayout()
                    if self.isNodeLoaded {
                        self.layoutIfNeeded()
                    }
                }
            )
        }

        if Thread.isMainThread {
            runUpdates()
        } else {
            DispatchQueue.main.async(execute: runUpdates)
        }
    }

    private func noteOverflowInteraction() {
        guard areOverflowActionsExpanded else { return }
        scheduleOverflowAutoCollapse()
    }

    private func scheduleOverflowAutoCollapse() {
        cancelOverflowAutoCollapse()
        guard areOverflowActionsExpanded else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.setOverflowActionsExpanded(false, animated: true)
        }
        overflowCollapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    private func cancelOverflowAutoCollapse() {
        overflowCollapseWorkItem?.cancel()
        overflowCollapseWorkItem = nil
    }

    private func resetSwipeReplyReveal(animated: Bool) {
        let apply: (Bool) -> Void = { [weak self] shouldAnimate in
            guard let self else { return }
            // Never force-load `.view` from a background Texture configure path.
            guard self.isNodeLoaded else { return }

            let updates = {
                self.swipeReplyRevealLabel.alpha = 0
                self.view.transform = .identity
            }
            let finish = {
                self.swipeReplyRevealLabel.isHidden = true
            }

            if shouldAnimate {
                UIView.animate(
                    withDuration: 0.2,
                    delay: 0,
                    options: [.beginFromCurrentState, .allowUserInteraction],
                    animations: updates,
                    completion: { _ in finish() }
                )
            } else {
                updates()
                finish()
            }
        }

        if Thread.isMainThread {
            apply(animated)
        } else {
            DispatchQueue.main.async {
                apply(false)
            }
        }
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
        guard let payload = currentPayload,
              payload.canWriteInteractions,
              !payload.post.hidden else {
            resetSwipeReplyReveal(animated: true)
            return
        }

        let translation = gestureRecognizer.translation(in: view)
        // Left swipe (negative x) opens reply — avoids fighting the nav-edge pop gesture.
        let slideDistance = min(max(-translation.x, 0), 72)
        let progress = max(0, min(slideDistance / Self.replySwipeTriggerThreshold, 1.6))

        switch gestureRecognizer.state {
        case .began, .changed:
            // Content slides left; reply cue peeks in from the trailing edge.
            view.transform = CGAffineTransform(translationX: -slideDistance, y: 0)
            if swipeReplyRevealLabel.superview == nil {
                view.addSubview(swipeReplyRevealLabel)
            }
            swipeReplyRevealLabel.isHidden = false
            swipeReplyRevealLabel.alpha = min(progress, 1)
            swipeReplyRevealLabel.sizeToFit()
            swipeReplyRevealLabel.center = CGPoint(
                x: bounds.width - 12 - swipeReplyRevealLabel.bounds.width / 2 + slideDistance,
                y: bounds.midY
            )

        case .ended, .cancelled, .failed:
            let shouldReply = translation.x < -Self.replySwipeTriggerThreshold
                && abs(translation.x) > abs(translation.y)
            resetSwipeReplyReveal(animated: true)
            if shouldReply, let callbacks = currentCallbacks {
                FireMotionHaptics.impact(.medium)
                callbacks.onSwipeReply(payload.post)
            }

        default:
            break
        }
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
            alert.addAction(UIAlertAction(title: "回复", style: .default) { _ in
                callbacks.onReplyPost(post)
            })
            alert.addAction(UIAlertAction(title: "回应", style: .default) { _ in
                callbacks.onToggleReactionPicker(post)
            })
            if post.canBoost {
                alert.addAction(UIAlertAction(title: "Boost", style: .default) { _ in
                    callbacks.onBoostPost(post)
                })
            }
            alert.addAction(UIAlertAction(title: "引用回复", style: .default) { _ in
                callbacks.onQuotePost(post)
            })
            alert.addAction(UIAlertAction(title: post.bookmarked ? "编辑书签" : "添加书签", style: .default) { _ in
                FireMotionHaptics.impact(.light)
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
        FireMotionHaptics.impact(.medium)
        presenter.present(alert, animated: true)
    }

    @objc private func handleReactionTap(_ sender: ASButtonNode) {
        guard let index = reactionButtons.firstIndex(of: sender),
              let payload = currentPayload,
              let callbacks = currentCallbacks,
              index < displayedReactions.count else {
            return
        }
        // Press bounce is owned by fireBindPressBounce(.chip).
        let reaction = displayedReactions[index]
        if reaction.id == "heart" {
            FireMotionHaptics.impact(.medium)
            callbacks.onToggleLike(payload.post)
        } else {
            FireMotionHaptics.impact(.light)
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

        return translation.x < 0
            && velocity.x <= 0
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
            let reply = UIAction(title: "回复", image: UIImage(systemName: "arrowshape.turn.up.left")) { _ in
                callbacks.onReplyPost(post)
            }
            reply.attributes = isMutating ? .disabled : []
            interactionActions.append(reply)

            let react = UIAction(title: "回应", image: UIImage(systemName: "face.smiling")) { _ in
                callbacks.onToggleReactionPicker(post)
            }
            react.attributes = isMutating ? .disabled : []
            interactionActions.append(react)

            if post.canBoost {
                let boost = UIAction(title: "Boost", image: UIImage(systemName: "bolt")) { _ in
                    callbacks.onBoostPost(post)
                }
                boost.attributes = isMutating ? .disabled : []
                interactionActions.append(boost)
            }

            let quote = UIAction(title: "引用回复", image: UIImage(systemName: "text.quote")) { _ in
                callbacks.onQuotePost(post)
            }
            quote.attributes = isMutating ? .disabled : []
            interactionActions.append(quote)

            let bookmarkTitle = post.bookmarked ? "编辑书签" : "添加书签"
            let bookmarkIcon = post.bookmarked ? "bookmark.fill" : "bookmark"
            let bookmark = UIAction(title: bookmarkTitle, image: UIImage(systemName: bookmarkIcon)) { _ in
                FireMotionHaptics.impact(.light)
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
                - FirePostCellLayoutCalculator.bodyLeadingOffset(for: depth),
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
            + FirePostCellLayoutCalculator.bodyLeadingOffset(for: currentDepth)
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
        let text = attributedText
        let apply = { [weak self] in
            guard let self else { return }
            self.richTextView?.attributedText = text
            (self.richTextView as? FireRichTextTextView)?.refreshQuotePreviewLayers()
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
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
        imageNode.cornerRadius = 4
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
        retryNode.backgroundColor = FireTheme.uiCanvas.withAlphaComponent(0.8)
        retryNode.addTarget(self, action: #selector(handleRetryTap), forControlEvents: .touchUpInside)
        retryNode.fireBindPressBounce(.compact)

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
        // May run on a decode queue — avoid UIScreen.main off the main thread.
        let scale: CGFloat = Thread.isMainThread ? UIScreen.main.scale : 3
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
    private static let chipHeight: CGFloat = FirePostCellLayoutCalculator.fixedBoostManualRowHeight
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

    func configure(
        boosts: [TopicPostBoostState],
        batchSignature: String,
        animationsEnabled: Bool,
        baseURLString: String
    ) {
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
            let chip = FirePostBoostChipView.styleForBarrage()
            chip.configure(
                boost: boost,
                attributedText: FirePostBoostDisplay.compactChipContent(
                    for: boost,
                    textColor: FireTheme.uiInk
                ),
                signature: FirePostBoostDisplay.contentSignature(for: boost),
                baseURLString: baseURLString
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
    private let avatarContainer = UIView()
    private let avatarImageView = UIImageView()
    private let monogramLabel = UILabel()
    private let textView = FireRichTextUIView()
    private let leadingInset = FirePostCellLayoutCalculator.boostChipLeadingInset
    private let trailingInset = FirePostCellLayoutCalculator.boostChipTrailingInset
    private let avatarTextSpacing = FirePostCellLayoutCalculator.boostChipAvatarTextSpacing
    private let avatarSize = FirePostCellLayoutCalculator.boostChipAvatarSize
    private var avatarLoadTask: Task<Void, Never>?
    private var avatarLoadGeneration: UInt64 = 0

    static func styleForManual() -> FirePostBoostChipView {
        FirePostBoostChipView(
            backgroundColor: FireTheme.uiAccent.withAlphaComponent(0.10),
            borderColor: FireTheme.uiAccent.withAlphaComponent(0.18)
        )
    }

    static func styleForBarrage() -> FirePostBoostChipView {
        FirePostBoostChipView(
            backgroundColor: FireTheme.uiSurface.withAlphaComponent(0.92),
            borderColor: FireTheme.uiAccent.withAlphaComponent(0.22)
        )
    }

    init(backgroundColor: UIColor, borderColor: UIColor? = nil) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        clipsToBounds = true
        self.backgroundColor = backgroundColor
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        if let borderColor {
            layer.borderWidth = 1.0 / UIScreen.main.scale
            layer.borderColor = borderColor.cgColor
        }

        avatarContainer.clipsToBounds = true
        avatarContainer.backgroundColor = FireTheme.uiAccent

        monogramLabel.font = UIFont.systemFont(ofSize: 9, weight: .bold)
        monogramLabel.textColor = .white
        monogramLabel.textAlignment = .center

        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.isHidden = true

        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = false
        textView.isUserInteractionEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.backgroundColor = .clear
        textView.textContainer.maximumNumberOfLines = 1
        textView.textContainer.lineBreakMode = .byTruncatingTail

        addSubview(avatarContainer)
        avatarContainer.addSubview(monogramLabel)
        avatarContainer.addSubview(avatarImageView)
        addSubview(textView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        boost: TopicPostBoostState,
        attributedText: NSAttributedString,
        signature: String,
        baseURLString: String
    ) {
        self.signature = signature
        textView.renderedContentID = "boost:\(signature)"
        textView.attributedText = attributedText
        configureAvatar(for: boost, baseURLString: baseURLString)
        setNeedsLayout()
    }

    private func configureAvatar(for boost: TopicPostBoostState, baseURLString: String) {
        avatarLoadTask?.cancel()
        avatarLoadTask = nil
        avatarLoadGeneration &+= 1
        let generation = avatarLoadGeneration

        let username = boost.user.username.trimmingCharacters(in: .whitespacesAndNewlines)
        monogramLabel.text = monogramForUsername(username: username.isEmpty ? "?" : username)
        avatarImageView.image = nil
        avatarImageView.isHidden = true

        guard let avatarURL = fireAvatarURL(
            avatarTemplate: boost.user.avatarTemplate,
            size: avatarSize,
            scale: UIScreen.main.scale,
            baseURLString: baseURLString
        ) else {
            return
        }

        let request = FireRemoteImageRequest(url: avatarURL)
        if let cached = FireRemoteImagePipeline.shared.cachedImage(for: request) {
            avatarImageView.image = cached
            avatarImageView.isHidden = false
            return
        }

        avatarLoadTask = Task { [weak self] in
            do {
                let image = try await FireRemoteImagePipeline.shared.loadImage(for: request)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.avatarLoadGeneration == generation else { return }
                    self.avatarImageView.image = image
                    self.avatarImageView.isHidden = false
                }
            } catch {
                return
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let avatarY = max((bounds.height - avatarSize) / 2, 0)
        avatarContainer.frame = CGRect(
            x: leadingInset,
            y: avatarY,
            width: avatarSize,
            height: avatarSize
        )
        avatarContainer.layer.cornerRadius = avatarSize / 2
        monogramLabel.frame = avatarContainer.bounds
        avatarImageView.frame = avatarContainer.bounds

        let textX = avatarContainer.frame.maxX + avatarTextSpacing
        let textWidth = max(bounds.width - textX - trailingInset, 1)
        let textFrame = CGRect(x: textX, y: 0, width: textWidth, height: bounds.height)
        let measuredHeight = measuredSingleLineTextSize(maxWidth: textWidth).height
        let verticalInset = max((bounds.height - measuredHeight) / 2, 0)
        if abs(textView.textContainerInset.top - verticalInset) > 0.5
            || abs(textView.textContainerInset.bottom - verticalInset) > 0.5 {
            textView.textContainerInset = UIEdgeInsets(
                top: verticalInset,
                left: 0,
                bottom: verticalInset,
                right: 0
            )
        }
        textView.frame = textFrame
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let textMaxWidth = max(size.width - leadingInset - trailingInset - avatarSize - avatarTextSpacing, 1)
        let textSize = FirePostBoostManualLayout.measuredSingleLineTextSize(
            attributedText: textView.attributedText,
            maxWidth: textMaxWidth
        )
        let width = min(
            textSize.width + leadingInset + trailingInset + avatarSize + avatarTextSpacing,
            size.width
        )
        return CGSize(width: max(width, avatarSize + leadingInset + trailingInset), height: size.height)
    }

    private func measuredSingleLineTextSize(maxWidth: CGFloat) -> CGSize {
        FirePostBoostManualLayout.measuredSingleLineTextSize(
            attributedText: textView.attributedText,
            maxWidth: maxWidth
        )
    }
}

struct FirePostBoostManualPlacement: Equatable {
    let rowIndex: Int
    let x: CGFloat
}

struct FirePostBoostManualLayoutResult: Equatable {
    let placements: [FirePostBoostManualPlacement]
    let contentWidth: CGFloat
    let usedRowCount: Int
}

enum FirePostBoostManualLayout {
    static let chipSpacing: CGFloat = 8

    static func placements(
        forChipWidths chipWidths: [CGFloat],
        pageWidth: CGFloat,
        laneCount: Int = 2,
        chipSpacing: CGFloat = chipSpacing
    ) -> FirePostBoostManualLayoutResult {
        let resolvedPageWidth = max(pageWidth, 1)
        let resolvedLaneCount = max(laneCount, 1)
        var pageStartX: CGFloat = 0
        var cursorXByRow = Array(repeating: CGFloat(0), count: resolvedLaneCount)
        var currentRowIndex = 0
        var placements: [FirePostBoostManualPlacement] = []
        placements.reserveCapacity(chipWidths.count)

        for rawChipWidth in chipWidths {
            let chipWidth = min(max(rawChipWidth, 1), resolvedPageWidth)
            var x = nextX(cursorX: cursorXByRow[currentRowIndex], chipSpacing: chipSpacing)
            if x + chipWidth > resolvedPageWidth {
                if currentRowIndex + 1 < resolvedLaneCount {
                    currentRowIndex += 1
                    x = 0
                } else {
                    pageStartX += max(cursorXByRow.max() ?? 0, resolvedPageWidth) + chipSpacing
                    cursorXByRow = Array(repeating: CGFloat(0), count: resolvedLaneCount)
                    currentRowIndex = 0
                    x = 0
                }
            }
            placements.append(FirePostBoostManualPlacement(rowIndex: currentRowIndex, x: pageStartX + x))
            cursorXByRow[currentRowIndex] = x + chipWidth
        }

        let contentWidth = max(pageStartX + (cursorXByRow.max() ?? 0), resolvedPageWidth)
        let usedRowCount = placements.reduce(0) { partialResult, placement in
            max(partialResult, placement.rowIndex + 1)
        }
        return FirePostBoostManualLayoutResult(
            placements: placements,
            contentWidth: contentWidth,
            usedRowCount: usedRowCount
        )
    }

    static func chipWidth(
        for attributedText: NSAttributedString?,
        maxWidth: CGFloat,
        nonTextWidth: CGFloat,
        minWidth: CGFloat
    ) -> CGFloat {
        let textSize = measuredSingleLineTextSize(
            attributedText: attributedText,
            maxWidth: max(maxWidth - nonTextWidth, 1)
        )
        return min(max(textSize.width + nonTextWidth, minWidth), max(maxWidth, 1))
    }

    static func measuredSingleLineTextSize(
        attributedText: NSAttributedString?,
        maxWidth: CGFloat
    ) -> CGSize {
        guard let attributedText,
              attributedText.length > 0 else {
            return .zero
        }
        let textStorage = NSTextStorage(attributedString: attributedText)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: CGSize(
            width: max(maxWidth, 1),
            height: .greatestFiniteMagnitude
        ))
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 1
        textContainer.lineBreakMode = .byTruncatingTail
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        guard glyphRange.length > 0 else {
            return .zero
        }
        let usedRect = layoutManager.usedRect(for: textContainer)
        return CGSize(
            width: min(ceil(usedRect.width), max(maxWidth, 1)),
            height: ceil(usedRect.height)
        )
    }

    private static func nextX(cursorX: CGFloat, chipSpacing: CGFloat) -> CGFloat {
        cursorX <= 0 ? 0 : cursorX + chipSpacing
    }
}

// MARK: - Fixed Boost Manual Scroller

private final class FirePostBoostManualScrollerView: UIView {
    private static let laneCount = 2
    private static let chipHeight: CGFloat = FirePostCellLayoutCalculator.fixedBoostManualRowHeight

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

    func configure(boosts: [TopicPostBoostState], baseURLString: String) {
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
            let chip = FirePostBoostChipView.styleForManual()
            chip.configure(
                boost: boost,
                attributedText: FirePostBoostDisplay.compactChipContent(
                    for: boost,
                    textColor: FireTheme.uiSubtleInk
                ),
                signature: FirePostBoostDisplay.contentSignature(for: boost),
                baseURLString: baseURLString
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
        let chipWidths = chips.map { chip in
            let measured = chip.sizeThatFits(CGSize(width: maxChipWidth, height: Self.chipHeight))
            return min(max(measured.width, 48), maxChipWidth)
        }
        let manualLayout = FirePostBoostManualLayout.placements(
            forChipWidths: chipWidths,
            pageWidth: bounds.width,
            laneCount: Self.laneCount
        )

        for (index, chip) in chips.enumerated() {
            guard index < manualLayout.placements.count else {
                continue
            }
            let placement = manualLayout.placements[index]
            let rowIndex = min(max(placement.rowIndex, 0), rowViews.count - 1)
            if chip.superview !== rowViews[rowIndex] {
                rowViews[rowIndex].addSubview(chip)
            }
            chip.frame = CGRect(
                x: placement.x,
                y: max((rowHeight - Self.chipHeight) / 2, 0),
                width: chipWidths[index],
                height: Self.chipHeight
            )
            chip.alpha = 1
            chip.transform = .identity
        }

        let contentWidth = manualLayout.contentWidth
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

/// Horizontal scroller for the inline quick-reaction strip so narrow devices
/// never clip trailing emoji buttons.
private final class FireInlineReactionPickerScrollNode: ASScrollNode {
    var buttons: [ASButtonNode] = [] {
        didSet { setNeedsLayout() }
    }

    override init() {
        super.init()
        automaticallyManagesSubnodes = true
        automaticallyManagesContentSize = true
        scrollableDirections = [.left, .right]
    }

    override func didLoad() {
        super.didLoad()
        view.showsHorizontalScrollIndicator = false
        view.showsVerticalScrollIndicator = false
        view.alwaysBounceHorizontal = true
        view.alwaysBounceVertical = false
        view.clipsToBounds = true
        view.contentInsetAdjustmentBehavior = .never
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let row = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: FirePostCellLayoutCalculator.reactionPickerButtonSpacing,
            justifyContent: .start,
            alignItems: .center,
            children: buttons
        )
        // Keep vertical centering inside the strip height.
        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 2, left: 0, bottom: 2, right: 8),
            child: row
        )
    }
}
