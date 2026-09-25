import AsyncDisplayKit
import UIKit

extension FirePostCellNode {
    func configureReplyShortcut(payload: FirePostCellRenderPayload) {
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
        let dynamicTint = expanded ? Self.accentTextColor : Self.tertiaryInkColor
        let tint = FireTextureAttributedText.resolvedColor(dynamicTint, with: payload.colorTraits)
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

    @objc func handleReplyContextTap() {
        guard let payload = currentPayload,
              let postNumber = payload.replyTargetPostNumber,
              postNumber > 0,
              let callbacks = currentCallbacks else {
            return
        }
        callbacks.onOpenReplyTarget(postNumber)
    }

    @objc func handleActionQuoteTap() {
        guard let payload = currentPayload, let callbacks = currentCallbacks else { return }
        noteOverflowInteraction()
        FireMotionHaptics.impact(.light)
        callbacks.onQuotePost(payload.post)
        setOverflowActionsExpanded(false, animated: true)
    }

    @objc func handleReplyShortcutTap() {
        guard let payload = currentPayload,
              let callbacks = currentCallbacks else {
            return
        }
        // Toggle must work even while nested replies are still loading.
        FireMotionHaptics.impact(.light)
        callbacks.onOpenReplies(payload.post)
    }
}
