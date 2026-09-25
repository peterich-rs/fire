import AsyncDisplayKit
import UIKit

extension FirePostCellNode {
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
}
