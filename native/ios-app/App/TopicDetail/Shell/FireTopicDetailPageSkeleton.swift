import Foundation

/// Topic detail is four regions. Each region refreshes on its own.
///
/// The article and the comment list share one scrolling feed so the post
/// scrolls away and the navigation title can pin. They are still separate
/// item slices: a title or stats change reuses the comment slice.
enum FireTopicDetailPageRegion: Equatable {
    /// Navigation bar. The system back button is the leading slot.
    case titleBar
    /// Original post: title and tags, body, reaction icons, stats.
    case article
    /// Reply rows plus the floor header and footer.
    case comments
    /// Bottom quick-reply bar. It is not a feed row.
    case composer
}

/// Slots inside the navigation title bar. Each one applies on its own.
enum FireTopicDetailTitleBarSlot: Equatable {
    /// System back button. The page does not rebuild it.
    case leading
    case title
    case trailing
}

/// Slots inside the quick-reply bar.
enum FireTopicDetailComposerSlot: Equatable {
    case typing
    case replyTarget
    case input
    case validation
}

/// Bands inside one post cell, original post or a comment row.
enum FireTopicDetailMessageBand: Equatable, Hashable, CaseIterable, Sendable {
    case author
    /// "回复 @用户" quote entry. The quoted paragraph stays in the text segment.
    case quote
    case images
    case text
    /// Collapsed body expand, and the reply-count control that opens the floor.
    case showMore
    case actions
    case reactions
    /// Vertical floor line and row divider. Not the expand control.
    case thread
}

struct FireTopicDetailMessageBands: Equatable, Sendable {
    var author: AnyHashable
    var quote: AnyHashable
    var images: AnyHashable
    var text: AnyHashable
    var showMore: AnyHashable
    var actions: AnyHashable
    var reactions: AnyHashable
    var thread: AnyHashable

    func changed(from previous: FireTopicDetailMessageBands) -> Set<FireTopicDetailMessageBand> {
        var bands: Set<FireTopicDetailMessageBand> = []
        if author != previous.author { bands.insert(.author) }
        if quote != previous.quote { bands.insert(.quote) }
        if images != previous.images { bands.insert(.images) }
        if text != previous.text { bands.insert(.text) }
        if showMore != previous.showMore { bands.insert(.showMore) }
        if actions != previous.actions { bands.insert(.actions) }
        if reactions != previous.reactions { bands.insert(.reactions) }
        if thread != previous.thread { bands.insert(.thread) }
        return bands
    }
}

/// Bands inside the original post. Title, stats, and the vote row are their own cells.
/// Body and reactions stay on the original-post cell and update through `messageBands`.
enum FireTopicDetailArticleBand: Equatable {
    case titleAndTags
    case summary
    case body
    case reactions
    case stats
    case topicVote
}

/// Comment list pieces. A message row is one floor; the header and footer
/// are the floor chrome around that list.
enum FireTopicDetailCommentBand: Equatable {
    case floorHeader
    case notice
    case placeholder
    case message
    case floorFooter
}

extension FireTopicDetailRuntimeItemKind {
    var pageRegion: FireTopicDetailPageRegion {
        switch self {
        case .header, .aiSummary, .originalPost, .stats, .topicVote:
            return .article
        case .repliesHeader, .bodyState, .reply, .replyFooter, .notice:
            return .comments
        }
    }

    var articleBand: FireTopicDetailArticleBand? {
        switch self {
        case .header:
            return .titleAndTags
        case .aiSummary:
            return .summary
        case .originalPost:
            return .body
        case .stats:
            return .stats
        case .topicVote:
            return .topicVote
        case .repliesHeader, .bodyState, .reply, .replyFooter, .notice:
            return nil
        }
    }

    var commentBand: FireTopicDetailCommentBand? {
        switch self {
        case .repliesHeader:
            return .floorHeader
        case .notice:
            return .notice
        case .bodyState:
            return .placeholder
        case .reply:
            return .message
        case .replyFooter:
            return .floorFooter
        case .header, .aiSummary, .originalPost, .stats, .topicVote:
            return nil
        }
    }
}

extension FireTopicDetailRuntimeItem {
    var pageRegion: FireTopicDetailPageRegion { kind.pageRegion }
}

extension FireTopicDetailRuntimeSnapshot {
    var articleItems: [FireTopicDetailRuntimeItem] {
        items.filter { $0.pageRegion == .article }
    }

    var commentItems: [FireTopicDetailRuntimeItem] {
        items.filter { $0.pageRegion == .comments }
    }
}
