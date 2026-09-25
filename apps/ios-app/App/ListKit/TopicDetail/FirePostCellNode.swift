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

    deinit {
        avatarLoadTask?.cancel()
    }
}
