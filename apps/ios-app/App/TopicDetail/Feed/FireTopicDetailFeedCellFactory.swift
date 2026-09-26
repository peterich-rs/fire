import AsyncDisplayKit
import UIKit

final class FireTopicDetailFeedCellFactory: NSObject {
    var configuration: FireTopicDetailRuntimeConfiguration?
    var onRequestLoadMore: (() -> Void)?

    func makeCellNode(
        for item: FireTopicDetailRuntimeItem,
        configuration: FireTopicDetailRuntimeConfiguration,
        layoutWidth: CGFloat,
        appearance: FireAppearanceSnapshot
    ) -> ASCellNode {
        switch item.kind {
        case .header:
            return FireTopicDetailHeaderCellNode(configuration: configuration, appearance: appearance)
        case .aiSummary:
            return FireTopicDetailAISummaryCellNode(configuration: configuration, appearance: appearance)
        case .stats:
            return makeStatsCellNode(
                configuration: configuration,
                layoutWidth: layoutWidth,
                appearance: appearance
            )
        case .topicVote:
            let node = FireTopicDetailVoteChromeNode()
            node.apply(
                item: item,
                configuration: configuration,
                appearance: appearance
            )
            return node
        case .repliesHeader:
            return makeRepliesHeaderCellNode(configuration: configuration, appearance: appearance)
        case .replyFooter:
            return makeReplyFooterCellNode(
                for: item,
                configuration: configuration,
                appearance: appearance
            )
        case .bodyState:
            return makeBodyStateCellNode(configuration: configuration, appearance: appearance)
        case .notice:
            let node = FireTopicDetailNoticeChromeNode()
            node.onRetry = { [weak self] in
                Task { await self?.configuration?.onLoadTopicDetail() }
            }
            node.apply(
                item: item,
                configuration: configuration,
                appearance: appearance
            )
            return node
        case .originalPost, .reply:
            return makeMissingPostCellNode(appearance: appearance)
        }
    }
}
