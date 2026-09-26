import AsyncDisplayKit
import UIKit

extension FirePostCellNode {
    func configurePolls(payload: FirePostCellRenderPayload) {
        let pollModels = FirePostPollRenderModel.models(from: payload.post.polls)
        guard !pollModels.isEmpty else {
            pollContainerNode.isHidden = true
            if !pollViews.isEmpty || !pollSignature.isEmpty {
                rebuildPollViews([], [], payload: payload)
            }
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
}
