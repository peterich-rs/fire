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
            return makeTopicVoteCellNode(configuration: configuration, appearance: appearance)
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
            return makeTextCellNode(
                for: item,
                configuration: configuration,
                appearance: appearance
            )
        case .originalPost, .reply:
            return makeMissingPostCellNode(appearance: appearance)
        }
    }
}
