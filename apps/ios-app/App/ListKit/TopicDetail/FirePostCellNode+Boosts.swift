import AsyncDisplayKit
import UIKit

extension FirePostCellNode {
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
}
