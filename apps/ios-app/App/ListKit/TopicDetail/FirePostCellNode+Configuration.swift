import AsyncDisplayKit
import UIKit

extension FirePostCellNode {
    func performOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

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

    func applyBands(
        _ bands: Set<FireTopicDetailMessageBand>,
        payload: FirePostCellRenderPayload,
        callbacks: FirePostCellCallbacks,
        showsThreadLine: Bool,
        relayout: Bool
    ) {
        // Tap handlers read `currentPayload`, so adopt it even when no band
        // needs a redraw.
        currentPayload = payload
        currentCallbacks = callbacks
        currentShowsThreadLine = showsThreadLine
        currentShowsDivider = payload.showsDivider
        if relayout {
            currentLayoutWidth = payload.layoutWidth
            currentResolvedLayout = payload.layout
        }
        guard !bands.isEmpty || relayout else { return }
        if bands.contains(.author) {
            configureAvatar(payload: payload, avatarSize: currentAvatarSize)
            configureMeta(payload: payload)
        }
        if bands.contains(.quote) {
            configureQuote(payload: payload)
        }
        if bands.contains(.images) {
            applyImageBand(payload: payload)
        }
        if bands.contains(.text) {
            applyTextBand(payload: payload)
            configurePolls(payload: payload)
            boostAnimationsEnabled = payload.boostAnimationsEnabled
            configureBoosts(payload: payload)
        }
        if bands.contains(.showMore) {
            configureBodyContent(payload: payload)
            configureReplyShortcut(payload: payload)
        }
        if bands.contains(.actions) {
            applyInPlaceActionMutatingState(payload)
            updatePollInteractionState(payload: payload)
            configureSearchHighlight(payload.isSearchHighlighted)
        }
        if bands.contains(.reactions) {
            configureReactionPicker(payload: payload)
            if relayout {
                configureReactions(payload: payload)
            } else {
                applyInPlaceReactions(payload)
            }
        }
        if bands.contains(.thread) {
            configureThreadLine(shows: currentShowsThreadLine)
            configureDivider(shows: payload.showsDivider)
        }
        if relayout {
            setNeedsLayout()
        }
    }

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
}
