import Foundation

enum FireTopicDetailRuntimeSection: Sendable {
    case main
}

struct FireTopicDetailStatusMessage: Hashable, Sendable {
    let title: String?
    let message: String
    let retryable: Bool
    let emphasizesError: Bool
}

enum FireTopicDetailRuntimeItemKind: Hashable, Sendable {
    case header
    case aiSummary
    case originalPost
    case stats
    case topicVote
    case repliesHeader
    case bodyState
    case reply
    case replyFooter
    case notice
}

/// In-place token for post rows: the row's interaction identity plus every
/// band, so any band change is also an in-place change.
struct FireTopicDetailPostInPlaceToken: Hashable, Sendable {
    let interaction: String
    let bands: FireTopicDetailMessageBands
}

struct FireTopicDetailRuntimeItem: Hashable, @unchecked Sendable {
    let id: String
    let kind: FireTopicDetailRuntimeItemKind
    let postID: UInt64?
    let postNumber: UInt32?
    let replyIndex: Int?
    let replyShowsThreadLine: Bool
    let replyShowsDivider: Bool
    let replyShortcutCount: UInt32?
    let isReplyThreadExpanded: Bool
    let contentToken: AnyHashable
    let inPlaceUpdateToken: AnyHashable?
    let messageBands: FireTopicDetailMessageBands?
    let statusMessage: FireTopicDetailStatusMessage?

    init(
        id: String,
        kind: FireTopicDetailRuntimeItemKind,
        postID: UInt64?,
        postNumber: UInt32?,
        replyIndex: Int?,
        replyShowsThreadLine: Bool = false,
        replyShowsDivider: Bool = false,
        replyShortcutCount: UInt32? = nil,
        isReplyThreadExpanded: Bool = false,
        contentToken: AnyHashable,
        inPlaceUpdateToken: AnyHashable? = nil,
        messageBands: FireTopicDetailMessageBands? = nil,
        statusMessage: FireTopicDetailStatusMessage? = nil
    ) {
        self.id = id
        self.kind = kind
        self.postID = postID
        self.postNumber = postNumber
        self.replyIndex = replyIndex
        self.replyShowsThreadLine = replyShowsThreadLine
        self.replyShowsDivider = replyShowsDivider
        self.replyShortcutCount = replyShortcutCount
        self.isReplyThreadExpanded = isReplyThreadExpanded
        self.contentToken = contentToken
        self.inPlaceUpdateToken = inPlaceUpdateToken
        self.messageBands = messageBands
        self.statusMessage = statusMessage
    }

    /// Identity-only equality for diff planning. Use `hasSameRenderedContent`
    /// when comparing what the reader should actually see on screen.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    func hasSameRenderedContent(as other: Self) -> Bool {
        id == other.id
            && kind == other.kind
            && postID == other.postID
            && postNumber == other.postNumber
            && replyShortcutCount == other.replyShortcutCount
            && isReplyThreadExpanded == other.isReplyThreadExpanded
            && contentToken == other.contentToken
            && statusMessage == other.statusMessage
    }

    func needsVisibleNodeUpdate(comparedTo other: Self) -> Bool {
        hasSameRenderedContent(as: other)
            && inPlaceUpdateToken != other.inPlaceUpdateToken
    }

    func changedMessageBands(from previous: FireTopicDetailRuntimeItem) -> Set<FireTopicDetailMessageBand> {
        guard let messageBands, let previousBands = previous.messageBands else {
            return Set(FireTopicDetailMessageBand.allCases)
        }
        return messageBands.changed(from: previousBands)
    }
}
