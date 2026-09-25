import AsyncDisplayKit
import UIKit

extension FirePostCellNode {
    func configureReactionPicker(payload: FirePostCellRenderPayload) {
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

    func applyInPlaceReactions(_ payload: FirePostCellRenderPayload) {
        // Same chip IDs only rewrite titles / selection. ID-set changes are
        // applied here too; the feed decides whether to relayout the row.
        configureReactions(payload: payload)
    }

    func configureReactions(payload: FirePostCellRenderPayload) {
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
            canWrite: payload.canWriteInteractions
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

    func rebuildReactionButtons(_ reactions: [TopicReactionState], payload: FirePostCellRenderPayload) {
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

    func updateReactionButtons(_ reactions: [TopicReactionState], payload: FirePostCellRenderPayload) {
        for (button, reaction) in zip(reactionButtons, reactions) {
            configureReactionButton(button, reaction: reaction, payload: payload)
        }
    }

    func configureReactionButton(
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
        let reactionInk = FireTextureAttributedText.ink(
            with: currentPayload?.colorTraits ?? .current
        )
        let title = NSMutableAttributedString(
            string: "\(symbolString)\u{200A}",
            attributes: [.font: emojiFont, .foregroundColor: reactionInk]
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

    @objc func handleQuickReactionTap(_ sender: ASButtonNode) {
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

    @objc func handleReactionTap(_ sender: ASButtonNode) {
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
}
