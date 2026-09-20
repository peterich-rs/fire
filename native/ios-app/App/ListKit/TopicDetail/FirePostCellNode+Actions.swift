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

    func configureOverflowActions(payload: FirePostCellRenderPayload) {
        let canWrite = payload.canWriteInteractions && !payload.post.hidden
        let isMutating = payload.isMutating
        let showsChrome = payload.showsInlineActions
        let canBoost = canWrite && payload.post.canBoost
        let hasSecondary = canWrite
            || payload.post.canEdit
            || payload.post.canRecover
            || (payload.post.canDelete && !payload.post.hidden)

        // Primary actions stay visible so reply/react/boost are not buried under `...`.
        // Shared `isMutating` only dims 表情. Reply / boost stay live during a like.
        setActionVisible(
            actionReplyNode,
            visible: showsChrome && canWrite,
            enabled: FirePostCellActionAvailability.isEnabled(.reply, canUse: canWrite, isMutating: isMutating)
        )
        setActionVisible(
            actionReactNode,
            visible: showsChrome && canWrite,
            enabled: FirePostCellActionAvailability.isEnabled(.react, canUse: canWrite, isMutating: isMutating)
        )
        setActionVisible(
            actionBoostNode,
            visible: showsChrome && canBoost,
            enabled: FirePostCellActionAvailability.isEnabled(.boost, canUse: canBoost, isMutating: isMutating)
        )
        applyActionSymbol(actionBoostNode, systemName: "bolt", highlighted: false)

        let showsOverflow = showsChrome && hasSecondary
        overflowNode.isHidden = !showsOverflow
        overflowNode.isEnabled = FirePostCellActionAvailability.isEnabled(
            .overflow,
            canUse: showsOverflow,
            isMutating: isMutating
        )
        overflowNode.alpha = 1
        applyActionSymbol(
            actionReactNode,
            systemName: "face.smiling",
            highlighted: payload.isReactionPickerExpanded
        )
        applyActionSymbol(overflowNode, systemName: "ellipsis.circle", highlighted: areOverflowActionsExpanded)

        let expanded = showsOverflow && areOverflowActionsExpanded

        setActionVisible(
            actionQuoteNode,
            visible: expanded && canWrite,
            enabled: FirePostCellActionAvailability.isEnabled(.quote, canUse: canWrite, isMutating: isMutating)
        )

        let bookmarked = payload.post.bookmarked
        applyActionSymbol(
            actionBookmarkNode,
            systemName: bookmarked ? "bookmark.fill" : "bookmark",
            highlighted: bookmarked
        )
        actionBookmarkNode.accessibilityLabel = bookmarked ? "编辑书签" : "添加书签"
        setActionVisible(
            actionBookmarkNode,
            visible: expanded && canWrite,
            enabled: FirePostCellActionAvailability.isEnabled(.bookmark, canUse: canWrite, isMutating: isMutating)
        )

        setActionVisible(
            actionEditNode,
            visible: expanded && payload.post.canEdit,
            enabled: FirePostCellActionAvailability.isEnabled(
                .edit,
                canUse: payload.post.canEdit,
                isMutating: isMutating
            )
        )
        setActionVisible(
            actionFlagNode,
            visible: expanded && canWrite,
            enabled: FirePostCellActionAvailability.isEnabled(.flag, canUse: canWrite, isMutating: isMutating)
        )
    }

    /// Restore reply/boost and dim/undim only 表情 without resetting overflow expansion.
    func applyInPlaceActionMutatingState(_ payload: FirePostCellRenderPayload) {
        let canWrite = payload.canWriteInteractions && !payload.post.hidden
        let canBoost = canWrite && payload.post.canBoost
        let isMutating = payload.isMutating
        setActionEnabled(
            actionReplyNode,
            enabled: FirePostCellActionAvailability.isEnabled(.reply, canUse: canWrite, isMutating: isMutating)
        )
        setActionEnabled(
            actionReactNode,
            enabled: FirePostCellActionAvailability.isEnabled(.react, canUse: canWrite, isMutating: isMutating)
        )
        setActionEnabled(
            actionBoostNode,
            enabled: FirePostCellActionAvailability.isEnabled(.boost, canUse: canBoost, isMutating: isMutating)
        )
        if !overflowNode.isHidden {
            overflowNode.isEnabled = FirePostCellActionAvailability.isEnabled(
                .overflow,
                canUse: true,
                isMutating: isMutating
            )
            overflowNode.alpha = 1
        }
        setActionEnabled(
            actionQuoteNode,
            enabled: FirePostCellActionAvailability.isEnabled(.quote, canUse: canWrite, isMutating: isMutating)
        )
        setActionEnabled(
            actionBookmarkNode,
            enabled: FirePostCellActionAvailability.isEnabled(.bookmark, canUse: canWrite, isMutating: isMutating)
        )
        setActionEnabled(
            actionEditNode,
            enabled: FirePostCellActionAvailability.isEnabled(
                .edit,
                canUse: payload.post.canEdit,
                isMutating: isMutating
            )
        )
        setActionEnabled(
            actionFlagNode,
            enabled: FirePostCellActionAvailability.isEnabled(.flag, canUse: canWrite, isMutating: isMutating)
        )
    }

    func configureActionIcon(
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

    func applyActionSymbol(
        _ button: ASButtonNode,
        systemName: String,
        highlighted: Bool
    ) {
        let traits = currentPayload?.colorTraits ?? .current
        let dynamicTint = highlighted ? Self.accentTextColor : Self.tertiaryInkColor
        // Bake a static tint so alwaysOriginal SF Symbols track light/dark rebinds.
        let tint = FireTextureAttributedText.resolvedColor(dynamicTint, with: traits)
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        if let image = UIImage(systemName: systemName, withConfiguration: config)?
            .withTintColor(tint, renderingMode: .alwaysOriginal) {
            button.setImage(image, for: .normal)
        }
        button.imageNode.contentMode = .center
    }

    func setActionVisible(_ button: ASButtonNode, visible: Bool, enabled: Bool) {
        button.isHidden = !visible
        setActionEnabled(button, enabled: enabled)
    }

    func setActionEnabled(_ button: ASButtonNode, enabled: Bool) {
        guard !button.isHidden else { return }
        button.isEnabled = enabled
        button.alpha = enabled ? 1 : 0.45
    }

    func menuAttributes(
        for kind: FirePostCellActionKind,
        isMutating: Bool,
        destructive: Bool = false
    ) -> UIMenuElement.Attributes {
        var attributes: UIMenuElement.Attributes = []
        if destructive {
            attributes.insert(.destructive)
        }
        if !FirePostCellActionAvailability.isEnabled(kind, canUse: true, isMutating: isMutating) {
            attributes.insert(.disabled)
        }
        return attributes
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

    @objc func handleOverflowTap() {
        guard currentPayload?.showsInlineActions == true else { return }
        if areOverflowActionsExpanded {
            setOverflowActionsExpanded(false, animated: true)
        } else {
            setOverflowActionsExpanded(true, animated: true)
            scheduleOverflowAutoCollapse()
        }
    }

    @objc func handleActionReplyTap() {
        guard let payload = currentPayload, let callbacks = currentCallbacks else { return }
        FireMotionHaptics.impact(.light)
        callbacks.onReplyPost(payload.post)
    }

    @objc func handleActionReactTap() {
        guard let payload = currentPayload, let callbacks = currentCallbacks else { return }
        FireMotionHaptics.impact(.light)
        callbacks.onToggleReactionPicker(payload.post)
    }

    @objc func handleActionBoostTap() {
        guard let payload = currentPayload, let callbacks = currentCallbacks else { return }
        FireMotionHaptics.impact(.light)
        callbacks.onBoostPost(payload.post)
    }

    @objc func handleActionQuoteTap() {
        guard let payload = currentPayload, let callbacks = currentCallbacks else { return }
        noteOverflowInteraction()
        FireMotionHaptics.impact(.light)
        callbacks.onQuotePost(payload.post)
        setOverflowActionsExpanded(false, animated: true)
    }

    @objc func handleActionBookmarkTap() {
        guard let payload = currentPayload, let callbacks = currentCallbacks else { return }
        noteOverflowInteraction()
        FireMotionHaptics.impact(.light)
        callbacks.onBookmarkPost(payload.post)
        setOverflowActionsExpanded(false, animated: true)
    }

    @objc func handleActionEditTap() {
        guard let payload = currentPayload, let callbacks = currentCallbacks else { return }
        noteOverflowInteraction()
        callbacks.onEditPost(payload.post)
        setOverflowActionsExpanded(false, animated: true)
    }

    @objc func handleActionFlagTap() {
        guard let payload = currentPayload, let callbacks = currentCallbacks else { return }
        noteOverflowInteraction()
        callbacks.onFlagPost(payload.post)
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

    func setOverflowActionsExpanded(_ expanded: Bool, animated: Bool) {
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

    func noteOverflowInteraction() {
        guard areOverflowActionsExpanded else { return }
        scheduleOverflowAutoCollapse()
    }

    func scheduleOverflowAutoCollapse() {
        cancelOverflowAutoCollapse()
        guard areOverflowActionsExpanded else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.setOverflowActionsExpanded(false, animated: true)
        }
        overflowCollapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    func cancelOverflowAutoCollapse() {
        overflowCollapseWorkItem?.cancel()
        overflowCollapseWorkItem = nil
    }

    func resetSwipeReplyReveal(animated: Bool) {
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

    @objc func handleSwipePan(_ gestureRecognizer: UIPanGestureRecognizer) {
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

    @objc func handleMenuTap() {
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
            let react = UIAlertAction(title: "回应", style: .default) { _ in
                callbacks.onToggleReactionPicker(post)
            }
            react.isEnabled = FirePostCellActionAvailability.isEnabled(
                .react,
                canUse: true,
                isMutating: isMutating
            )
            alert.addAction(react)
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
        alert.popoverPresentationController?.sourceView = menuNode.view
        alert.popoverPresentationController?.sourceRect = menuNode.view.bounds
        FireMotionHaptics.impact(.medium)
        presenter.present(alert, animated: true)
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
        let location = touch.location(in: view)
        if gestureRecognizer === profileTapGestureRecognizer {
            return profileHitRects().contains(where: { $0.contains(location) })
        }
        guard gestureRecognizer === swipeGestureRecognizer else {
            return true
        }
        return canBeginReplySwipe(at: location)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === swipeGestureRecognizer || otherGestureRecognizer === swipeGestureRecognizer
    }

    // MARK: - Menu

    func buildMenu(for post: TopicPostState, callbacks: FirePostCellCallbacks, canWrite: Bool, isMutating: Bool) -> UIMenu {
        var actions: [UIMenu] = []

        if post.canEdit {
            let edit = UIAction(title: "编辑", image: UIImage(systemName: "pencil")) { _ in
                callbacks.onEditPost(post)
            }
            edit.attributes = menuAttributes(for: .edit, isMutating: isMutating)
            actions.append(UIMenu(options: .displayInline, children: [edit]))
        }

        var interactionActions: [UIAction] = []
        if canWrite && !post.hidden {
            let reply = UIAction(title: "回复", image: UIImage(systemName: "arrowshape.turn.up.left")) { _ in
                callbacks.onReplyPost(post)
            }
            reply.attributes = menuAttributes(for: .reply, isMutating: isMutating)
            interactionActions.append(reply)

            let react = UIAction(title: "回应", image: UIImage(systemName: "face.smiling")) { _ in
                callbacks.onToggleReactionPicker(post)
            }
            react.attributes = menuAttributes(for: .react, isMutating: isMutating)
            interactionActions.append(react)

            if post.canBoost {
                let boost = UIAction(title: "Boost", image: UIImage(systemName: "bolt")) { _ in
                    callbacks.onBoostPost(post)
                }
                boost.attributes = menuAttributes(for: .boost, isMutating: isMutating)
                interactionActions.append(boost)
            }

            let quote = UIAction(title: "引用回复", image: UIImage(systemName: "text.quote")) { _ in
                callbacks.onQuotePost(post)
            }
            quote.attributes = menuAttributes(for: .quote, isMutating: isMutating)
            interactionActions.append(quote)

            let bookmarkTitle = post.bookmarked ? "编辑书签" : "添加书签"
            let bookmarkIcon = post.bookmarked ? "bookmark.fill" : "bookmark"
            let bookmark = UIAction(title: bookmarkTitle, image: UIImage(systemName: bookmarkIcon)) { _ in
                FireMotionHaptics.impact(.light)
                callbacks.onBookmarkPost(post)
            }
            bookmark.attributes = menuAttributes(for: .bookmark, isMutating: isMutating)
            interactionActions.append(bookmark)

            let flag = UIAction(title: "举报", image: UIImage(systemName: "flag")) { _ in
                callbacks.onFlagPost(post)
            }
            flag.attributes = menuAttributes(for: .flag, isMutating: isMutating)
            interactionActions.append(flag)
        }

        if post.canRecover {
            let recover = UIAction(title: "恢复", image: UIImage(systemName: "arrow.uturn.backward")) { _ in
                callbacks.onRecoverPost(post)
            }
            recover.attributes = menuAttributes(for: .recover, isMutating: isMutating)
            interactionActions.append(recover)
        }

        if post.canDelete && !post.hidden {
            let delete = UIAction(title: "删除", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                callbacks.onDeletePost(post)
            }
            delete.attributes = menuAttributes(for: .delete, isMutating: isMutating, destructive: true)
            interactionActions.append(delete)
        }

        if !interactionActions.isEmpty {
            actions.append(UIMenu(options: .displayInline, children: interactionActions))
        }

        return UIMenu(children: actions)
    }

    func replySwipeActivationRect() -> CGRect {
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

    func canBeginReplySwipe(at location: CGPoint) -> Bool {
        if location.x <= 44 {
            return false
        }
        guard replySwipeActivationRect().contains(location) else {
            return false
        }
        return !isTouchInsideInteractiveContent(at: location)
    }

    func isTouchInsideInteractiveContent(at location: CGPoint) -> Bool {
        guard let hitView = view.hitTest(location, with: nil) else {
            return false
        }
        if hitView.isDescendant(ofType: UITextView.self) {
            return true
        }
        if hitView.isDescendant(ofType: UIControl.self) {
            return true
        }
        if profileHitRects().contains(where: { $0.contains(location) }) {
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
}
