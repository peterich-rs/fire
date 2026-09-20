import AsyncDisplayKit
import UIKit

final class FirePostCellNode: ASCellNode, UIGestureRecognizerDelegate {
    static let replySwipeTriggerThreshold: CGFloat = 55

    static let accentTextColor = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.96, green: 0.45, blue: 0.22, alpha: 1)
        }
        return UIColor(red: 0.91, green: 0.39, blue: 0.18, alpha: 1)
    }
    static let tertiaryInkColor = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.62, green: 0.63, blue: 0.67, alpha: 1)
        }
        return UIColor(red: 0.52, green: 0.52, blue: 0.55, alpha: 1)
    }
    /// Idle reaction chips stay nearly transparent — avoid muddy tertiary fills.
    static let reactionIdleFillColor = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(white: 1.0, alpha: 0.06)
        }
        return UIColor.clear
    }
    static let reactionIdleBorderColor = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(white: 1.0, alpha: 0.12)
        }
        return UIColor(white: 0.0, alpha: 0.08)
    }
    static let reactionIdleLabelColor = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(white: 0.78, alpha: 1)
        }
        return UIColor(white: 0.36, alpha: 1)
    }
    static let reactionMineFillColor = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.96, green: 0.45, blue: 0.22, alpha: 0.18)
        }
        return UIColor(red: 0.91, green: 0.39, blue: 0.18, alpha: 0.10)
    }
    static let reactionMineBorderColor = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.96, green: 0.45, blue: 0.22, alpha: 0.55)
        }
        return UIColor(red: 0.91, green: 0.39, blue: 0.18, alpha: 0.45)
    }

    // MARK: - Nodes

    let avatarNode = ASImageNode()
    let avatarMonogramNode = ASTextNode()
    let avatarContainerNode = ASDisplayNode()
    let threadLineNode = ASDisplayNode()
    let usernameNode = ASTextNode()
    let authorBadgeNode = ASTextNode()
    let authorMetadataNode = ASTextNode()
    let replyContextNode = ASButtonNode()
    let timestampNode = ASTextNode()
    let acceptedAnswerNode = ASTextNode()
    let postNumberNode = ASTextNode()
    let menuNode = ASButtonNode()
    let bodyTextNode = ASTextNode()
    let bodySelectableTextNode = FireSelectableRichTextNode()
    let imageContainerNode = ASDisplayNode()
    let pollContainerNode = ASDisplayNode()
    let boostContainerNode = ASDisplayNode()
    let replyShortcutNode = ASButtonNode()
    /// Always-visible primary actions + overflow for secondary tools.
    let actionReplyNode = ASButtonNode()
    let actionReactNode = ASButtonNode()
    let actionBoostNode = ASButtonNode()
    let overflowNode = ASButtonNode()
    let actionQuoteNode = ASButtonNode()
    let actionBookmarkNode = ASButtonNode()
    let actionEditNode = ASButtonNode()
    let actionFlagNode = ASButtonNode()
    let reactionPickerScrollNode = FireInlineReactionPickerScrollNode()
    var reactionPickerButtons: [ASButtonNode] = []
    var reactionPickerOptionIDs: [String] = []
    var areOverflowActionsExpanded = false
    var overflowCollapseWorkItem: DispatchWorkItem?
    lazy var swipeReplyRevealLabel: UILabel = {
        let label = UILabel()
        label.text = "回复"
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = Self.accentTextColor
        label.alpha = 0
        label.isHidden = true
        return label
    }()
    lazy var boostBarrageNode: ASDisplayNode = {
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
    let reactionContainerNode = ASDisplayNode()
    let dividerNode = ASDisplayNode()

    // MARK: - State

    var currentPayload: FirePostCellRenderPayload?
    var currentCallbacks: FirePostCellCallbacks?
    var currentDepth: Int = 0
    var currentShowsThreadLine: Bool = false
    var currentShowsDivider: Bool = false
    var currentAvatarSize: CGFloat = 32
    var currentAvatarSpacing: CGFloat = 10
    var currentLayoutWidth: CGFloat = 0
    var currentResolvedLayout: FirePostCellLayout?
    var currentContentSizeCategory: UIContentSizeCategory = .large
    /// Captured on main in `didLoad`; safe for Texture background configure paths.
    var cachedDisplayScale: CGFloat = 3
    static var lastKnownContentSizeCategory: UIContentSizeCategory = .large
    var renderedContentID: String?
    var avatarSignature: String?
    var avatarLoadTask: Task<Void, Never>?
    var avatarLoadGeneration: UInt64 = 0
    var contentSegmentNodes: [ASDisplayNode] = []
    var contentSegmentSignature: [String] = []
    var pollViews: [FirePostPollView] = []
    var pollHeights: [CGFloat] = []
    var pollSignature: [String] = []
    var pollWidth: CGFloat = 0
    lazy var boostManualScrollerNode: ASDisplayNode = {
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
    var boostSignature: [String] = []
    var boostBarrageBoosts: [TopicPostBoostState] = []
    var boostBarrageLines: [String] = []
    var boostBarrageBatchSignature = ""
    var boostManualBoosts: [TopicPostBoostState] = []
    var boostAnimationsEnabled = true
    var reactionButtons: [ASButtonNode] = []
    var reactionButtonIDs: [String] = []
    var displayedReactions: [TopicReactionState] = []
    var reactionSignature: String?
    var linkDelegate: RichTextNodeLinkDelegate?
    lazy var swipeGestureRecognizer = UIPanGestureRecognizer(
        target: self,
        action: #selector(handleSwipePan(_:))
    )
    /// Cell-owned tap, same view as swipe-to-reply. Subnode `ASControlNode` overlays
    /// do not track touches (Texture: ASControlNode is not for direct use), and UIKit
    /// recognizers on Texture child views lose to `ASCollectionNode` scrolling.
    lazy var profileTapGestureRecognizer: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleProfileTapGesture(_:)))
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
        profileTapGestureRecognizer.delegate = self
        view.addGestureRecognizer(swipeGestureRecognizer)
        view.addGestureRecognizer(profileTapGestureRecognizer)
        // Re-bind resolved colors once the node is in a real view hierarchy.
        refreshResolvedColorsFromLiveTraitsIfNeeded()
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

    override func didEnterVisibleState() {
        super.didEnterVisibleState()
        refreshResolvedColorsFromLiveTraitsIfNeeded()
    }

    /// Re-bake Texture text colors after theme / trait changes (window override or system).
    /// Soft rebind only — does not tear down image nodes or reset overflow/swipe state.
    func applyColorAppearance(_ appearance: FireAppearanceSnapshot) {
        guard let payload = currentPayload else {
            FireAppearanceTexture.applySnapshot(appearance, to: self)
            setNeedsDisplay()
            return
        }
        guard payload.appearance.token != appearance.token else {
            // Already baked for this appearance; still refresh canvas in case highlight state moved.
            configureSearchHighlight(payload.isSearchHighlighted)
            return
        }
        let updated = payload.withAppearance(appearance)
        currentPayload = updated
        // Force text rebind when appearance flips, but keep `contentSegmentSignature` so
        // FirePostImageNode instances are not destroyed mid-load (blank image placeholders).
        renderedContentID = nil
        configureMeta(payload: updated)
        configureBodyContent(payload: updated)
        configureReplyShortcut(payload: updated)
        configureOverflowActions(payload: updated)
        configureReactionPicker(payload: updated)
        configureReactions(payload: updated)
        configureSearchHighlight(updated.isSearchHighlighted)
        setNeedsDisplay()
    }

    /// Compatibility entry for call sites that still hold traits only.
    func applyColorAppearance(_ colorTraits: UITraitCollection) {
        applyColorAppearance(FireAppearanceEnvironment.snapshot(traits: colorTraits))
    }

    func refreshResolvedColorsFromLiveTraitsIfNeeded() {
        guard isNodeLoaded, currentPayload != nil else { return }
        applyColorAppearance(FireAppearanceEnvironment.snapshot(for: view))
    }

    func setupNodes() {
        backgroundColor = FireTheme.uiCanvas
        // Prefer stable body text display; meta is short and cheap to redraw sync.
        bodyTextNode.displaysAsynchronously = false
        usernameNode.displaysAsynchronously = false
        authorMetadataNode.displaysAsynchronously = false
        postNumberNode.displaysAsynchronously = false
        timestampNode.displaysAsynchronously = false

        // Avatar
        avatarContainerNode.isUserInteractionEnabled = false
        avatarContainerNode.clipsToBounds = true
        avatarContainerNode.cornerRadius = 16
        avatarContainerNode.backgroundColor = .systemBlue
        avatarNode.contentMode = .scaleAspectFill
        avatarNode.clipsToBounds = true
        avatarNode.cornerRadius = 16
        avatarNode.isHidden = true
        avatarNode.alpha = 0
        avatarNode.isUserInteractionEnabled = false
        avatarMonogramNode.isLayerBacked = true
        avatarMonogramNode.isUserInteractionEnabled = false
        avatarContainerNode.isAccessibilityElement = true
        avatarContainerNode.accessibilityTraits = .button
        avatarContainerNode.accessibilityLabel = "查看用户资料"
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
        usernameNode.isLayerBacked = false
        usernameNode.style.flexShrink = 1.0
        usernameNode.isUserInteractionEnabled = false
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
    func performOnMain(_ work: @escaping () -> Void) {
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

    /// Count / selection / mutating updates. Does not rebuild the row or reset overflow.
    func applyInPlaceInteraction(
        payload: FirePostCellRenderPayload,
        callbacks: FirePostCellCallbacks
    ) {
        currentPayload = payload
        currentCallbacks = callbacks
        applyInPlaceActionMutatingState(payload)
        applyInPlaceReactions(payload)
        updatePollInteractionState(payload: payload)
        configureSearchHighlight(payload.isSearchHighlighted)
    }

    /// Height-changing local updates (body expand, picker, first reaction chip).
    /// Relayouts this row only and leaves overflow expansion alone.
    func applyVisibleRowRelayout(
        payload: FirePostCellRenderPayload,
        callbacks: FirePostCellCallbacks
    ) {
        currentPayload = payload
        currentCallbacks = callbacks
        currentLayoutWidth = payload.layoutWidth
        currentResolvedLayout = payload.layout
        configureBodyContent(payload: payload)
        configureReactionPicker(payload: payload)
        applyInPlaceActionMutatingState(payload)
        applyInPlaceReactions(payload)
        configureReplyShortcut(payload: payload)
        configureSearchHighlight(payload.isSearchHighlighted)
    }

    func configureSearchHighlight(_ isHighlighted: Bool) {
        let appearance = currentPayload?.appearance
            ?? FireAppearanceEnvironment.snapshot(traits: .current)
        let accent = FireTextureAttributedText.resolvedColor(
            Self.accentTextColor,
            with: appearance.traits
        )
        backgroundColor = isHighlighted
            ? accent.withAlphaComponent(0.10)
            : appearance.canvas
        borderWidth = isHighlighted ? 1 : 0
        borderColor = isHighlighted
            ? accent.withAlphaComponent(0.70).cgColor
            : UIColor.clear.cgColor
        cornerRadius = isHighlighted ? 8 : 0
        clipsToBounds = isHighlighted
    }

    func configureAvatar(payload: FirePostCellRenderPayload, avatarSize: CGFloat) {
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

    func configureThreadLine(shows: Bool) {
        threadLineNode.isHidden = !shows
        threadLineNode.style.preferredSize = CGSize(width: 1, height: shows ? 1 : 0)
        threadLineNode.style.flexGrow = shows ? 1.0 : 0.0
    }

    func configureMeta(payload: FirePostCellRenderPayload) {
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

        let appearance = payload.appearance
        let primaryInk = appearance.ink
        let secondaryInk = appearance.subtleInk
        let tertiaryInk = appearance.tertiaryInk

        usernameNode.attributedText = NSAttributedString(
            string: FirePostAuthorMetadataDisplay.displayName(for: payload.post),
            attributes: [.font: subheadlineFont, .foregroundColor: primaryInk]
        )
        let canOpenProfile = !payload.post.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        avatarContainerNode.accessibilityLabel = canOpenProfile
            ? "查看 \(FirePostAuthorMetadataDisplay.displayName(for: payload.post)) 的资料"
            : "查看用户资料"

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
                    .foregroundColor: secondaryInk,
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
            attributes: [.font: captionFont, .foregroundColor: tertiaryInk]
        )

        if payload.post.acceptedAnswer {
            acceptedAnswerNode.isHidden = false
            acceptedAnswerNode.attributedText = acceptedAnswerAttributedText()
        } else {
            acceptedAnswerNode.isHidden = true
        }

        postNumberNode.attributedText = NSAttributedString(
            string: "#\(payload.post.postNumber)楼",
            attributes: [.font: monoCaptionFont, .foregroundColor: tertiaryInk]
        )

        // Header `...` is retired — overflow lives in the bottom action strip.
        menuNode.isHidden = true
        menuNode.isEnabled = false
    }


    func configurePolls(payload: FirePostCellRenderPayload) {
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

    func updatePollInteractionState(payload: FirePostCellRenderPayload) {
        let canWrite = payload.canWriteInteractions
        let isMutating = payload.isMutating
        performOnMain { [weak self] in
            guard let self else { return }
            for view in self.pollViews {
                view.updateInteractionState(canInteract: canWrite, isMutating: isMutating)
            }
        }
    }

    func rebuildPollViews(
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

    func configureBoosts(payload: FirePostCellRenderPayload) {
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

    func configureFixedBoostManualScroller(boosts: [TopicPostBoostState]) {
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

    func fixedBoostManualScrollerHeight(availableWidth: CGFloat) -> CGFloat {
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

    func configureBoostBarrage(boosts: [TopicPostBoostState], batchSignature: String) {
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


    func configureDivider(shows: Bool) {
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
        var avatarColumnChildren: [ASLayoutElement] = [avatarContainerNode]
        if !threadLineNode.isHidden {
            avatarColumnChildren.append(threadLineNode)
        }
        let avatarColumn = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 0,
            justifyContent: .start,
            alignItems: .center,
            children: avatarColumnChildren
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




    @objc func handleImageTap(_ sender: FirePostImageNode) {
        currentCallbacks?.onOpenImage(sender.image)
    }

    @objc func handleProfileTapGesture(_ gesture: UITapGestureRecognizer) {
        _ = handleProfileTap(at: gesture.location(in: view))
    }

    /// Shared by the cell tap recognizer and tests. Uses live node frames when
    /// loaded, otherwise the precomputed `avatarFrame` / `metaFrame`.
    @discardableResult
    func handleProfileTap(at point: CGPoint) -> Bool {
        guard profileHitRects().contains(where: { $0.contains(point) }) else {
            return false
        }
        guard let username = currentPayload?.post.username.trimmingCharacters(in: .whitespacesAndNewlines),
              !username.isEmpty else {
            return false
        }
        FireMotionHaptics.selection()
        currentCallbacks?.onOpenProfile(username)
        return true
    }

    func profileHitRects() -> [CGRect] {
        var rects: [CGRect] = []
        if isNodeLoaded {
            let avatar = avatarContainerNode.view.convert(avatarContainerNode.view.bounds, to: view)
            if !avatar.isNull, avatar.width > 1, avatar.height > 1 {
                rects.append(avatar.insetBy(dx: -8, dy: -8))
            }
            if !usernameNode.isHidden {
                let name = usernameNode.view.convert(usernameNode.view.bounds, to: view)
                if !name.isNull, name.width > 1, name.height > 1 {
                    rects.append(name.insetBy(dx: -4, dy: -6))
                }
            }
        }
        if let layout = currentResolvedLayout {
            rects.append(layout.avatarFrame.insetBy(dx: -8, dy: -8))
            let meta = layout.metaFrame
            if !meta.isNull, !meta.isEmpty {
                rects.append(
                    CGRect(x: meta.minX, y: meta.minY, width: min(meta.width, 168), height: meta.height)
                        .insetBy(dx: -4, dy: -6)
                )
            }
        }
        if rects.isEmpty {
            let indent = FirePostCellLayoutCalculator.indentWidth(for: currentDepth)
            rects.append(
                CGRect(
                    x: FirePostCellLayoutCalculator.outerHorizontalPadding + indent,
                    y: 0,
                    width: currentAvatarSize,
                    height: currentAvatarSize
                ).insetBy(dx: -8, dy: -8)
            )
        }
        return rects
    }




    // MARK: - Helpers

    func acceptedAnswerAttributedText() -> NSAttributedString {
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

    static func badgeAttributedText(parts: [String]) -> NSAttributedString {
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

    static func reactionSignatureString(
        reactions: [TopicReactionState],
        currentUserReactionID: String?,
        canWrite: Bool
    ) -> String {
        let reactionTokens = reactions.map { reaction in
            [reaction.id, String(reaction.count), String(reaction.canUndo ?? true)].joined(separator: ":")
        }.joined(separator: "|")
        return [
            reactionTokens,
            currentUserReactionID ?? "",
            String(canWrite),
        ].joined(separator: "\u{1F}")
    }




    func showLoadedAvatar() {
        avatarNode.alpha = 1
    }

    func showAvatarFallback() {
        avatarNode.alpha = 0
    }

    func cancelAvatarLoad() {
        avatarLoadTask?.cancel()
        avatarLoadTask = nil
        avatarLoadGeneration &+= 1
        avatarNode.image = nil
        showAvatarFallback()
    }

    func loadAvatar(url: URL) {
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

    func applyLoadedAvatar(_ image: UIImage, generation: UInt64) {
        guard generation == avatarLoadGeneration else { return }
        avatarNode.image = image
        showLoadedAvatar()
    }

    func applyFailedAvatarLoad(generation: UInt64) {
        guard generation == avatarLoadGeneration else { return }
        avatarNode.image = nil
        showAvatarFallback()
    }

    deinit {
        avatarLoadTask?.cancel()
    }

    func nearestViewController() -> UIViewController? {
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

extension UIView {
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
