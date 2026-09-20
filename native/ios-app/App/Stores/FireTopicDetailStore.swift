import Foundation

enum FireTopicDetailSearchDirection {
    case backward
    case forward
}

struct FireTopicDetailPagePayload: Sendable {
    let sourceSnapshot: TopicDetailSourceSnapshotState
    let treePresentation: TopicTreePresentationState
}

/// Pure data product of a topic-detail page payload, prepared off the main actor.
struct FirePreparedTopicDetailPage: Sendable {
    let treePresentation: TopicTreePresentationState
    let detail: TopicDetailState
    let postLookup: [UInt64: TopicPostState]
    let suggestedUnreadRootPostNumber: UInt32?
}

struct FireTopicDetailFeedContentToken: Equatable {
    let header: FireTopicDetailFeedHeaderToken
    let stream: [UInt64]
    let posts: [FireTopicPostContentToken]

    init(detail: TopicDetailState) {
        header = FireTopicDetailFeedHeaderToken(detail: detail)
        stream = detail.postStream.stream
        posts = detail.postStream.posts.map(FireTopicPostContentToken.init(post:))
    }
}

struct FireTopicDetailFeedHeaderToken: Equatable {
    let id: UInt64
    let messageBusLastId: Int64?
    let title: String
    let postsCount: UInt32
    let categoryId: UInt64?
    let tagNames: [String]
    let views: UInt32
    let likeCount: UInt32
    let createdAt: String?
    let lastReadPostNumber: UInt32?
    let bookmarks: [UInt64]
    let acceptedAnswer: Bool
    let hasAcceptedAnswer: Bool
    let canVote: Bool
    let voteCount: Int32
    let userVoted: Bool
    let summarizable: Bool
    let hasCachedSummary: Bool
    let hasSummary: Bool
    let archetype: String?
    let participants: [FireTopicParticipantContentToken]

    init(detail: TopicDetailState) {
        id = detail.id
        messageBusLastId = detail.messageBusLastId
        title = detail.title
        postsCount = detail.postsCount
        categoryId = detail.categoryId
        tagNames = detail.tags.map(\.name)
        views = detail.views
        likeCount = detail.likeCount
        createdAt = detail.createdAt
        lastReadPostNumber = detail.lastReadPostNumber
        bookmarks = detail.bookmarks
        acceptedAnswer = detail.acceptedAnswer
        hasAcceptedAnswer = detail.hasAcceptedAnswer
        canVote = detail.canVote
        voteCount = detail.voteCount
        userVoted = detail.userVoted
        summarizable = detail.summarizable
        hasCachedSummary = detail.hasCachedSummary
        hasSummary = detail.hasSummary
        archetype = detail.archetype
        participants = detail.details.participants.map(FireTopicParticipantContentToken.init(participant:))
    }
}

struct FireTopicDetailChromeContentToken: Equatable {
    let id: UInt64
    let title: String
    let slug: String
    let bookmarked: Bool
    let bookmarkId: UInt64?
    let bookmarkName: String?
    let bookmarkReminderAt: String?
    let notificationLevel: Int32?
    let canEdit: Bool
    let archetype: String?

    init(detail: TopicDetailState) {
        id = detail.id
        title = detail.title
        slug = detail.slug
        bookmarked = detail.bookmarked
        bookmarkId = detail.bookmarkId
        bookmarkName = detail.bookmarkName
        bookmarkReminderAt = detail.bookmarkReminderAt
        notificationLevel = detail.details.notificationLevel
        canEdit = detail.details.canEdit
        archetype = detail.archetype
    }
}

struct FireTopicParticipantContentToken: Equatable {
    let userId: UInt64
    let username: String?
    let name: String?

    init(participant: TopicParticipantState) {
        userId = participant.userId
        username = participant.username
        name = participant.name
    }
}

struct FireTopicPostContentToken: Equatable {
    let id: UInt64
    let username: String
    let name: String?
    let avatarTemplate: String?
    let presentationLength: Int
    let presentationChecksum: UInt64
    let rawLength: Int
    let rawChecksum: UInt64
    let postNumber: UInt32
    let postType: Int32
    let createdAt: String?
    let updatedAt: String?
    let replyCount: UInt32
    let replyToPostNumber: UInt32?
    let replyToUsername: String?
    let bookmarked: Bool
    let bookmarkId: UInt64?
    let bookmarkName: String?
    let bookmarkReminderAt: String?
    let polls: [FireTopicPollContentToken]
    let acceptedAnswer: Bool
    let canAcceptAnswer: Bool
    let canUnacceptAnswer: Bool
    let canEdit: Bool
    let canDelete: Bool
    let canRecover: Bool
    let hidden: Bool

    init(post: TopicPostState) {
        id = post.id
        username = post.username
        name = post.name
        avatarTemplate = post.avatarTemplate
        presentationLength = post.presentation?.plainText().utf8.count ?? 0
        presentationChecksum = post.presentation?.checksum() ?? 0
        rawLength = post.raw?.utf8.count ?? 0
        rawChecksum = post.raw.map(Self.checksum) ?? 0
        postNumber = post.postNumber
        postType = post.postType
        createdAt = post.createdAt
        updatedAt = post.updatedAt
        replyCount = post.replyCount
        replyToPostNumber = post.replyToPostNumber
        replyToUsername = post.replyToUser?.username
        bookmarked = post.bookmarked
        bookmarkId = post.bookmarkId
        bookmarkName = post.bookmarkName
        bookmarkReminderAt = post.bookmarkReminderAt
        polls = post.polls.map(FireTopicPollContentToken.init(poll:))
        acceptedAnswer = post.acceptedAnswer
        canAcceptAnswer = post.canAcceptAnswer
        canUnacceptAnswer = post.canUnacceptAnswer
        canEdit = post.canEdit
        canDelete = post.canDelete
        canRecover = post.canRecover
        hidden = post.hidden
    }

    private static func checksum(_ value: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }
}

struct FireTopicPollContentToken: Equatable {
    let id: UInt64
    let name: String
    let kind: String
    let status: String
    let results: String
    let options: [FireTopicPollOptionContentToken]
    let voters: UInt32
    let userVotes: [String]

    init(poll: PollState) {
        id = poll.id
        name = poll.name
        kind = poll.kind
        status = poll.status
        results = poll.results
        options = poll.options.map(FireTopicPollOptionContentToken.init(option:))
        voters = poll.voters
        userVotes = poll.userVotes
    }
}

struct FireTopicPollOptionContentToken: Equatable {
    let id: String
    let plainText: String
    let htmlLength: Int
    let votes: UInt32

    init(option: PollOptionState) {
        id = option.id
        plainText = option.plainText
        htmlLength = option.html.utf8.count
        votes = option.votes
    }
}

@MainActor
final class FireTopicDetailStore: ObservableObject {
    nonisolated static let topicPostPageSize = 30
    nonisolated static let topicDetailInitialBatchSize: UInt16 = 40
    nonisolated static let topicDetailLoadMoreBatchSize: UInt16 = 40
    nonisolated static let topicPostPrefetchThreshold = 10
    nonisolated static let topicPostForwardExpansionSize = 60
    nonisolated static let replyContextPostBatchSize = 20
    nonisolated static let topicPostVisibleRangeDebounce = Duration.milliseconds(120)
    nonisolated static let topicPostHydrationIterationLimit = 8

    @Published var topicDetails: [UInt64: TopicDetailState] = [:]
    @Published var topicRenderStates: [UInt64: FireTopicDetailRenderState] = [:]
    @Published var topicPresenceUsersByTopic: [UInt64: [TopicPresenceUserState]] = [:]
    @Published var loadingMoreTopicPostIDs: Set<UInt64> = []
    @Published var loadMoreTopicPostErrorsByTopicID: [UInt64: String] = [:]
    @Published var loadingTopicIDs: Set<UInt64> = []
    @Published var submittingReplyTopicIDs: Set<UInt64> = []
    @Published var mutatingPostIDs: Set<UInt64> = []
    @Published var postActionTypes: [PostActionTypeState] = []
    @Published var isLoadingPostActionTypes = false
    @Published var postRepliesByPostID: [UInt64: [TopicPostState]] = [:]
    @Published var postReplyHistoryByPostID: [UInt64: [TopicPostState]] = [:]
    @Published var postReplyContextErrorsByPostID: [UInt64: String] = [:]
    @Published var loadingPostReplyContextIDs: Set<UInt64> = []
    @Published var topicAiSummaries: [UInt64: TopicAiSummaryState] = [:]
    @Published var loadingTopicAiSummaryIDs: Set<UInt64> = []
    @Published var unavailableTopicAiSummaryIDs: Set<UInt64> = []
    @Published var topicAiSummaryErrorsByTopicID: [UInt64: String] = [:]
    @Published var topicCollectionRevisions: [UInt64: UInt64] = [:]
    @Published var topicChromeRevisions: [UInt64: UInt64] = [:]
    @Published var topicSidecarRevisions: [UInt64: UInt64] = [:]
    @Published var topicInteractionRevisions: [UInt64: UInt64] = [:]
    @Published var errorMessagesByTopicID: [UInt64: String] = [:]

    let appViewModel: FireAppViewModel
    var topicSourceSnapshots: [UInt64: TopicDetailSourceSnapshotState] = [:]
    var topicDetailNoticesByTopic: [UInt64: FireTopicDetailStatusMessage] = [:]
    var topicRecoverySlugsByTopic: [UInt64: String] = [:]
    var topicTreePresentations: [UInt64: TopicTreePresentationState] = [:]
    var topicSourceCursorsByTopic: [UInt64: TopicSourceCursorState] = [:]
    var pendingTopicDetailRefreshTasks: [UInt64: Task<Void, Never>] = [:]
    var topicPresenceHeartbeatTasks: [UInt64: Task<Void, Never>] = [:]
    var topicPostPreloadTasks: [UInt64: Task<Void, Never>] = [:]
    var topicVisibleRangeTasks: [UInt64: Task<Void, Never>] = [:]
    var topicRenderTasks: [UInt64: Task<Void, Never>] = [:]
    var topicWindowStates: [UInt64: FireTopicDetailWindowState] = [:]
    var topicRenderCaches: [UInt64: FireTopicDetailRenderCache] = [:]
    var topicRenderGenerations: [UInt64: UInt64] = [:]
    var topicPostLookups: [UInt64: [UInt64: TopicPostState]] = [:]
    var topicDetailFeedContentTokens: [UInt64: FireTopicDetailFeedContentToken] = [:]
    var topicDetailChromeContentTokens: [UInt64: FireTopicDetailChromeContentToken] = [:]
    var topicScrollInteractionStates: [UInt64: Bool] = [:]
    var deferredTopicDetailRefreshTopicIDs: Set<UInt64> = []
    var deferredTopicDetailRefreshPayloads: [UInt64: FireTopicDetailPagePayload] = [:]
    var hydratingTopicPostIDs: Set<UInt64> = []
    var pendingVisiblePostNumbersByTopic: [UInt64: Set<UInt32>] = [:]
    var topicDetailTargetPostNumbers: [UInt64: UInt32] = [:]
    var activeTopicDetailOwnerTokens: [UInt64: Set<String>] = [:]
    var topicAiSummaryTasks: [UInt64: Task<Void, Never>] = [:]
    var hasLoadedPostActionTypes = false

    init(appViewModel: FireAppViewModel) {
        self.appViewModel = appViewModel
    }

    var renderBaseURLString: String {
        let trimmed = appViewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    func bumpTopicCollectionRevision(topicId: UInt64) {
        topicCollectionRevisions[topicId, default: 0] &+= 1
    }

    func bumpTopicChromeRevision(topicId: UInt64) {
        topicChromeRevisions[topicId, default: 0] &+= 1
    }

    func bumpTopicSidecarRevision(topicId: UInt64) {
        topicSidecarRevisions[topicId, default: 0] &+= 1
    }

    func bumpTopicInteractionRevision(topicId: UInt64) {
        topicInteractionRevisions[topicId, default: 0] &+= 1
    }

    func setLoadingTopic(_ isLoading: Bool, topicId: UInt64) {
        let changed: Bool
        if isLoading {
            changed = loadingTopicIDs.insert(topicId).inserted
        } else {
            changed = loadingTopicIDs.remove(topicId) != nil
        }
        if changed, topicDetails[topicId] == nil {
            bumpTopicCollectionRevision(topicId: topicId)
        }
    }

    func setLoadingMoreTopicPosts(_ isLoading: Bool, topicId: UInt64) {
        let changed: Bool
        if isLoading {
            changed = loadingMoreTopicPostIDs.insert(topicId).inserted
        } else {
            changed = loadingMoreTopicPostIDs.remove(topicId) != nil
        }
        if changed {
            bumpTopicCollectionRevision(topicId: topicId)
        }
    }

    func setLoadMoreTopicPostsError(_ message: String?, topicId: UInt64) {
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let previous = loadMoreTopicPostErrorsByTopicID[topicId] ?? ""
        if trimmed.isEmpty {
            loadMoreTopicPostErrorsByTopicID.removeValue(forKey: topicId)
        } else {
            loadMoreTopicPostErrorsByTopicID[topicId] = trimmed
        }
        if previous != trimmed {
            bumpTopicCollectionRevision(topicId: topicId)
        }
    }

    func setLoadingTopicAiSummary(_ isLoading: Bool, topicId: UInt64) {
        // Loading stays off the render path. Most topics have no summary, so publishing
        // loading transitions would only insert/remove empty chrome and jitter the feed.
        if isLoading {
            _ = loadingTopicAiSummaryIDs.insert(topicId)
        } else {
            _ = loadingTopicAiSummaryIDs.remove(topicId)
        }
    }

    func setMutatingPost(
        _ isMutating: Bool,
        topicId: UInt64,
        postId: UInt64
    ) {
        let changed: Bool
        if isMutating {
            changed = mutatingPostIDs.insert(postId).inserted
        } else {
            changed = mutatingPostIDs.remove(postId) != nil
        }
        if changed {
            bumpTopicInteractionRevision(topicId: topicId)
        }
    }

    func setSubmittingReply(
        _ isSubmitting: Bool,
        topicId: UInt64
    ) {
        let changed: Bool
        if isSubmitting {
            changed = submittingReplyTopicIDs.insert(topicId).inserted
        } else {
            changed = submittingReplyTopicIDs.remove(topicId) != nil
        }
        if changed {
            bumpTopicChromeRevision(topicId: topicId)
        }
    }

    func setLoadingPostReplyContext(
        _ isLoading: Bool,
        topicId: UInt64,
        postId: UInt64
    ) {
        let changed: Bool
        if isLoading {
            changed = loadingPostReplyContextIDs.insert(postId).inserted
        } else {
            changed = loadingPostReplyContextIDs.remove(postId) != nil
        }
        if changed {
            bumpTopicInteractionRevision(topicId: topicId)
        }
    }

    func setPostReplyContextError(
        _ message: String?,
        topicId: UInt64,
        postId: UInt64
    ) {
        let normalized = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextValue = normalized?.isEmpty == false ? normalized : nil
        guard postReplyContextErrorsByPostID[postId] != nextValue else {
            return
        }
        postReplyContextErrorsByPostID[postId] = nextValue
        bumpTopicInteractionRevision(topicId: topicId)
    }

    func setTopicPresenceUsers(
        _ users: [TopicPresenceUserState],
        topicId: UInt64
    ) {
        let previousUsers = topicPresenceUsersByTopic[topicId] ?? []
        if users.isEmpty {
            if !previousUsers.isEmpty {
                topicPresenceUsersByTopic.removeValue(forKey: topicId)
                bumpTopicChromeRevision(topicId: topicId)
            }
            return
        }
        guard previousUsers != users else { return }
        topicPresenceUsersByTopic[topicId] = users
        bumpTopicChromeRevision(topicId: topicId)
    }

    func setPendingScrollTarget(_ postNumber: UInt32?, topicId: UInt64) {
        let previous = topicDetailTargetPostNumbers[topicId]
        if let postNumber {
            topicDetailTargetPostNumbers[topicId] = postNumber
        } else {
            topicDetailTargetPostNumbers.removeValue(forKey: topicId)
        }
        if previous != postNumber {
            bumpTopicCollectionRevision(topicId: topicId)
        }
    }

    func updateTopicErrorMessage(_ message: String?, topicId: UInt64) {
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let previous = errorMessagesByTopicID[topicId] ?? ""
        if trimmed.isEmpty {
            errorMessagesByTopicID.removeValue(forKey: topicId)
        } else {
            errorMessagesByTopicID[topicId] = trimmed
        }
        if previous != trimmed {
            bumpTopicCollectionRevision(topicId: topicId)
        }
    }

    func updateTopicDetailNotice(
        _ notice: FireTopicDetailStatusMessage?,
        topicId: UInt64
    ) {
        let changed: Bool
        if let notice {
            changed = topicDetailNoticesByTopic[topicId] != notice
            topicDetailNoticesByTopic[topicId] = notice
        } else {
            changed = topicDetailNoticesByTopic.removeValue(forKey: topicId) != nil
        }
        if changed {
            bumpTopicCollectionRevision(topicId: topicId)
        }
    }

    func applySession(_ session: SessionState) {
        let readiness = session.readiness
        if readiness.canReadAuthenticatedApi {
            return
        }
        let isLoggedOut = !readiness.hasLoginCookie && !readiness.hasCurrentUser
        if isLoggedOut {
            appViewModel.topicDetailLogger()?.notice(
                "resetting topic detail store reason=logged-out topic_ids=\(Self.formattedTopicIDs(Set(topicDetails.keys)))"
            )
            reset()
        } else {
            appViewModel.topicDetailLogger()?.debug(
                "pausing topic detail fetches reason=transient-unauth retained_topic_ids=\(Self.formattedTopicIDs(Set(topicDetails.keys)))"
            )
            cancelInFlightFetches()
        }
    }

    func cancelInFlightFetches() {
        pendingTopicDetailRefreshTasks.values.forEach { $0.cancel() }
        pendingTopicDetailRefreshTasks = [:]
        topicPostPreloadTasks.values.forEach { $0.cancel() }
        topicPostPreloadTasks = [:]
        topicVisibleRangeTasks.values.forEach { $0.cancel() }
        topicVisibleRangeTasks = [:]
        topicRenderTasks.values.forEach { $0.cancel() }
        topicRenderTasks = [:]
        hydratingTopicPostIDs = []
        pendingVisiblePostNumbersByTopic = [:]
        loadingTopicIDs.removeAll()
        loadingMoreTopicPostIDs.removeAll()
        loadMoreTopicPostErrorsByTopicID.removeAll()
        errorMessagesByTopicID.removeAll()
        loadingPostReplyContextIDs.removeAll()
        topicAiSummaryTasks.values.forEach { $0.cancel() }
        topicAiSummaryTasks = [:]
        loadingTopicAiSummaryIDs.removeAll()
    }

    func handleMessageBusStopped() {
        pendingTopicDetailRefreshTasks.values.forEach { $0.cancel() }
        pendingTopicDetailRefreshTasks = [:]
        deferredTopicDetailRefreshTopicIDs = []
        deferredTopicDetailRefreshPayloads = [:]
        topicPresenceHeartbeatTasks.values.forEach { $0.cancel() }
        topicPresenceHeartbeatTasks = [:]
        let affectedTopicIDs = Array(topicPresenceUsersByTopic.keys)
        topicPresenceUsersByTopic = [:]
        affectedTopicIDs.forEach { bumpTopicChromeRevision(topicId: $0) }
    }

    func reset() {
        appViewModel.topicDetailLogger()?.notice(
            "resetting topic detail store topic_ids=\(Self.formattedTopicIDs(Set(topicDetails.keys))) loading_ids=\(Self.formattedTopicIDs(loadingTopicIDs))"
        )
        pendingTopicDetailRefreshTasks.values.forEach { $0.cancel() }
        pendingTopicDetailRefreshTasks = [:]
        topicPresenceHeartbeatTasks.values.forEach { $0.cancel() }
        topicPresenceHeartbeatTasks = [:]
        topicPostPreloadTasks.values.forEach { $0.cancel() }
        topicPostPreloadTasks = [:]
        topicVisibleRangeTasks.values.forEach { $0.cancel() }
        topicVisibleRangeTasks = [:]
        topicRenderTasks.values.forEach { $0.cancel() }
        topicRenderTasks = [:]
        topicAiSummaryTasks.values.forEach { $0.cancel() }
        topicAiSummaryTasks = [:]
        activeTopicDetailOwnerTokens = [:]
        topicScrollInteractionStates = [:]
        deferredTopicDetailRefreshTopicIDs = []
        deferredTopicDetailRefreshPayloads = [:]
        topicDetailTargetPostNumbers = [:]
        pendingVisiblePostNumbersByTopic = [:]
        topicWindowStates = [:]
        topicRenderCaches = [:]
        topicRenderGenerations = [:]
        topicPostLookups = [:]
        topicDetailFeedContentTokens = [:]
        topicDetailChromeContentTokens = [:]
        topicSourceSnapshots = [:]
        topicDetailNoticesByTopic = [:]
        topicRecoverySlugsByTopic = [:]
        topicTreePresentations = [:]
        topicSourceCursorsByTopic = [:]
        topicDetails = [:]
        topicRenderStates = [:]
        topicAiSummaries = [:]
        unavailableTopicAiSummaryIDs = []
        topicAiSummaryErrorsByTopicID = [:]
        topicCollectionRevisions = [:]
        topicChromeRevisions = [:]
        topicSidecarRevisions = [:]
        topicInteractionRevisions = [:]
        topicPresenceUsersByTopic = [:]
        loadingMoreTopicPostIDs = []
        loadMoreTopicPostErrorsByTopicID = [:]
        loadingTopicIDs = []
        loadingTopicAiSummaryIDs = []
        submittingReplyTopicIDs = []
        mutatingPostIDs = []
        postActionTypes = []
        isLoadingPostActionTypes = false
        postRepliesByPostID = [:]
        postReplyHistoryByPostID = [:]
        postReplyContextErrorsByPostID = [:]
        loadingPostReplyContextIDs = []
        hasLoadedPostActionTypes = false
        hydratingTopicPostIDs = []
        errorMessagesByTopicID = [:]
    }












    func clearTopicDetailAnchor(topicId: UInt64) {
        clearTransientAnchor(topicId: topicId)
    }

    func pendingScrollTarget(topicId: UInt64) -> UInt32? {
        topicDetailTargetPostNumbers[topicId]
    }

    func isScrollTargetExhausted(topicId: UInt64, postNumber: UInt32) -> Bool {
        guard let detail = topicDetails[topicId] else { return false }
        if detail.postStream.posts.contains(where: { $0.postNumber == postNumber }) {
            return false
        }
        return topicSourceCursorsByTopic[topicId] == nil
    }

    func markScrollTargetSatisfied(topicId: UInt64, postNumber: UInt32) {
        guard activeAnchorPostNumber(topicId: topicId) == postNumber
            || topicDetailTargetPostNumbers[topicId] == postNumber else {
            return
        }
        clearTransientAnchor(topicId: topicId)
    }

    func topicDetail(for topicId: UInt64) -> TopicDetailState? {
        topicDetails[topicId]
    }

    func topicRenderState(for topicId: UInt64) -> FireTopicDetailRenderState? {
        topicRenderStates[topicId]
    }

    func topicPostLookup(for topicId: UInt64) -> [UInt64: TopicPostState] {
        topicPostLookups[topicId] ?? [:]
    }

    func topicPresenceUsers(for topicId: UInt64) -> [TopicPresenceUserState] {
        topicPresenceUsersByTopic[topicId] ?? []
    }

    func topicAiSummary(for topicId: UInt64) -> TopicAiSummaryState? {
        topicAiSummaries[topicId]
    }

    func isLoadingTopicAiSummary(topicId: UInt64) -> Bool {
        loadingTopicAiSummaryIDs.contains(topicId)
    }

    func topicAiSummaryError(for topicId: UInt64) -> String? {
        topicAiSummaryErrorsByTopicID[topicId]
    }

    func detailNotice(topicId: UInt64) -> FireTopicDetailStatusMessage? {
        topicDetailNoticesByTopic[topicId]
    }

    func topicCollectionRevision(topicId: UInt64) -> UInt64 {
        topicCollectionRevisions[topicId] ?? 0
    }

    func topicSidecarRevision(topicId: UInt64) -> UInt64 {
        topicSidecarRevisions[topicId] ?? 0
    }

    func topicInteractionRevision(topicId: UInt64) -> UInt64 {
        topicInteractionRevisions[topicId] ?? 0
    }

    func isLoadingTopic(topicId: UInt64) -> Bool {
        loadingTopicIDs.contains(topicId)
    }

    func isLoadingMoreTopicPosts(topicId: UInt64) -> Bool {
        loadingMoreTopicPostIDs.contains(topicId)
    }

    func loadMoreTopicPostsError(topicId: UInt64) -> String? {
        loadMoreTopicPostErrorsByTopicID[topicId]
    }

    func errorMessage(for topicId: UInt64) -> String? {
        errorMessagesByTopicID[topicId]
    }

    func postReplies(for postID: UInt64) -> [TopicPostState]? {
        postRepliesByPostID[postID]
    }

    func postReplyHistory(for postID: UInt64) -> [TopicPostState]? {
        postReplyHistoryByPostID[postID]
    }

    func postReplyContextError(for postID: UInt64) -> String? {
        postReplyContextErrorsByPostID[postID]
    }

    func isLoadingPostReplyContext(postID: UInt64) -> Bool {
        loadingPostReplyContextIDs.contains(postID)
    }

    func hasMoreTopicPosts(topicId: UInt64) -> Bool {
        topicSourceCursorsByTopic[topicId] != nil
    }



    nonisolated static func canStartNextTopicSourcePageLoad(
        hasMoreTopicPosts: Bool,
        isLoadingMoreTopicPosts: Bool,
        hasPendingPreloadTask: Bool,
        hasLoadedDetail: Bool
    ) -> Bool {
        hasMoreTopicPosts
            && !isLoadingMoreTopicPosts
            && !hasPendingPreloadTask
            && hasLoadedDetail
    }











    func isSubmittingReply(topicId: UInt64) -> Bool {
        submittingReplyTopicIDs.contains(topicId)
    }

    func isMutatingPost(postId: UInt64) -> Bool {
        mutatingPostIDs.contains(postId)
    }










    nonisolated static func mergeReplyContextTreeRows(
        existingRows: [TopicTreeRowState],
        bodyPostNumber: UInt32,
        rootPost: TopicPostState,
        contextPosts: [TopicPostState]
    ) -> [TopicTreeRowState] {
        guard !contextPosts.isEmpty else {
            return existingRows
        }

        var rows = existingRows
        var rowIndexByPostID: [UInt64: Int] = [:]
        var rowByPostNumber: [UInt32: TopicTreeRowState] = [:]
        rowIndexByPostID.reserveCapacity(existingRows.count + contextPosts.count)
        rowByPostNumber.reserveCapacity(existingRows.count + contextPosts.count)
        for (index, row) in rows.enumerated() {
            rowIndexByPostID[row.postId] = index
            rowByPostNumber[row.postNumber] = row
        }

        let rootRow = rowByPostNumber[rootPost.postNumber]
        let fallbackRootPostNumber = rootRow?.rootPostNumber
            ?? rootPost.replyToPostNumber
            ?? bodyPostNumber
        let fallbackRootDepth = rootRow?.depth ?? (rootPost.postNumber == bodyPostNumber ? 0 : 1)
        var nextPreorderIndex = (rows.map(\.preorderIndex).max() ?? 0) + 1
        var nextSiblingIndexByParent = Dictionary(
            grouping: rows,
            by: { $0.parentPostNumber ?? bodyPostNumber }
        ).mapValues(\.count)

        let orderedContextPosts = FireTopicPresentation.uniqueTopicPostsPreservingOrder(contextPosts)
            .filter { post in
                post.id != rootPost.id && post.postNumber != bodyPostNumber
            }
            .sorted { lhs, rhs in
                if lhs.postNumber == rhs.postNumber {
                    return lhs.id < rhs.id
                }
                return lhs.postNumber < rhs.postNumber
            }

        let childCountsByParent = Dictionary(
            grouping: orderedContextPosts,
            by: { $0.replyToPostNumber ?? rootPost.postNumber }
        ).mapValues(\.count)

        for post in orderedContextPosts {
            if let existingIndex = rowIndexByPostID[post.id] {
                rowByPostNumber[post.postNumber] = rows[existingIndex]
                continue
            }

            let parentPostNumber = post.replyToPostNumber ?? rootPost.postNumber
            let parentRow = rowByPostNumber[parentPostNumber]
            let depth = parentRow.map { Int($0.depth) + 1 } ?? Int(fallbackRootDepth) + 1
            let rootPostNumber = parentRow?.rootPostNumber ?? fallbackRootPostNumber
            let siblingIndex = nextSiblingIndexByParent[parentPostNumber, default: 0]
            nextSiblingIndexByParent[parentPostNumber] = siblingIndex + 1
            let row = TopicTreeRowState(
                postId: post.id,
                postNumber: post.postNumber,
                rootPostNumber: rootPostNumber,
                parentPostNumber: parentPostNumber,
                depth: UInt16(clamping: depth),
                preorderIndex: nextPreorderIndex,
                hasChildren: (childCountsByParent[post.postNumber] ?? 0) > 0,
                descendantCount: post.replyCount,
                siblingIndex: UInt16(clamping: siblingIndex),
                isLastSibling: true
            )
            nextPreorderIndex += 1
            rowIndexByPostID[post.id] = rows.count
            rowByPostNumber[post.postNumber] = row
            rows.append(row)
        }

        return FireTopicPresentation.uniqueTreeRowsPreservingOrder(rows)
    }

















    static func formattedTopicIDs(_ topicIDs: Set<UInt64>) -> String {
        topicIDs.sorted().map(String.init).joined(separator: ",")
    }







    nonisolated static func renderStateCoversRowInputs(
        _ renderState: FireTopicDetailRenderState?,
        rowInputs: [FireTopicTimelineRowInput],
        originalPostID: UInt64?
    ) -> Bool {
        guard let renderState,
              let originalPostID,
              renderState.originalRow?.entry.postId == originalPostID else {
            return false
        }

        let expectedReplyIDs = rowInputs.dropFirst().map(\.postID)
        guard renderState.replyRows.map(\.entry.postId) == expectedReplyIDs else {
            return false
        }

        for rowInput in rowInputs {
            guard renderState.contentByPostID[rowInput.postID] != nil else {
                return false
            }
        }
        return true
    }

    nonisolated static func elapsedMilliseconds(since startedAt: Date) -> Int64 {
        Int64((Date().timeIntervalSince(startedAt) * 1_000).rounded())
    }

    nonisolated static func snapshotByAppending(
        _ appendedPosts: [TopicPostState],
        loadedRanges: [TopicLoadedRangeState],
        sourceCursor: TopicSourceCursorState?,
        sourceExhausted: Bool,
        onto snapshot: TopicDetailSourceSnapshotState
    ) -> TopicDetailSourceSnapshotState {
        var loaded = snapshot.loadedPosts
        var indexByID: [UInt64: Int] = Dictionary(
            uniqueKeysWithValues: loaded.enumerated().map { ($0.element.id, $0.offset) }
        )
        for post in appendedPosts {
            if let index = indexByID[post.id] {
                loaded[index] = post
            } else {
                indexByID[post.id] = loaded.count
                loaded.append(post)
            }
        }
        return TopicDetailSourceSnapshotState(
            header: snapshot.header,
            body: snapshot.body,
            rawStreamIds: snapshot.rawStreamIds,
            loadedPosts: loaded,
            loadedRanges: loadedRanges,
            sourceCursor: sourceCursor,
            sourceExhausted: sourceExhausted,
            focusedPostNumber: snapshot.focusedPostNumber
        )
    }

    nonisolated static func cookedByteCount(sourceSnapshot: TopicDetailSourceSnapshotState) -> Int {
        var seenPostIDs = Set<UInt64>()
        var total = 0
        for post in [sourceSnapshot.body.post] + sourceSnapshot.loadedPosts {
            if seenPostIDs.insert(post.id).inserted {
                total += post.presentation?.plainText().utf8.count ?? 0
            }
        }
        return total
    }










    static func hydrateRequestedRange(
        detail: TopicDetailState,
        window: FireTopicDetailWindowState,
        fetchPosts: @escaping @Sendable ([UInt64]) async throws -> [TopicPostState]
    ) async throws -> (detail: TopicDetailState, exhaustedPostIDs: Set<UInt64>) {
        var hydratedDetail = detail
        var exhaustedPostIDs = window.exhaustedPostIDs

        while true {
            let missingPostIDs = FireTopicPresentation.missingPostIDs(
                orderedPostIDs: hydratedDetail.postStream.stream,
                in: window.requestedRange,
                loadedPostIDs: Set(hydratedDetail.postStream.posts.map(\.id)),
                excluding: exhaustedPostIDs
            )
            guard !missingPostIDs.isEmpty else {
                return (hydratedDetail, exhaustedPostIDs)
            }

            let batchPostIDs = Array(missingPostIDs.prefix(topicPostPageSize))
            let fetchedPosts = try await fetchPosts(batchPostIDs)
            let returnedPostIDs = Set(fetchedPosts.map(\.id))
            exhaustedPostIDs.formUnion(
                batchPostIDs.filter { !returnedPostIDs.contains($0) }
            )

            guard !fetchedPosts.isEmpty else {
                continue
            }

            hydratedDetail.postStream.posts = FireTopicPresentation.mergeTopicPosts(
                existing: hydratedDetail.postStream.posts,
                incoming: fetchedPosts,
                orderedPostIDs: hydratedDetail.postStream.stream
            )
        }
    }
















    nonisolated static func nextDirectionalSearchRange(
        current: Range<Int>,
        totalCount: Int,
        direction: FireTopicDetailSearchDirection
    ) -> Range<Int>? {
        guard totalCount > 0 else {
            return nil
        }

        let pageSize = topicPostPageSize
        let maxWindowSize = FireTopicDetailWindowState.maxWindowSize
        let currentCount = current.count

        switch direction {
        case .backward:
            if current.lowerBound > 0 {
                return previousDirectionalSearchRange(
                    current: current,
                    totalCount: totalCount,
                    pageSize: pageSize,
                    maxWindowSize: maxWindowSize,
                    currentCount: currentCount
                )
            }
            guard current.upperBound < totalCount else {
                return nil
            }
            return nextForwardSearchRange(
                current: current,
                totalCount: totalCount,
                pageSize: pageSize,
                maxWindowSize: maxWindowSize,
                currentCount: currentCount
            )
        case .forward:
            if current.upperBound < totalCount {
                return nextForwardSearchRange(
                    current: current,
                    totalCount: totalCount,
                    pageSize: pageSize,
                    maxWindowSize: maxWindowSize,
                    currentCount: currentCount
                )
            }
            guard current.lowerBound > 0 else {
                return nil
            }
            return previousDirectionalSearchRange(
                current: current,
                totalCount: totalCount,
                pageSize: pageSize,
                maxWindowSize: maxWindowSize,
                currentCount: currentCount
            )
        }
    }

    nonisolated static func previousDirectionalSearchRange(
        current: Range<Int>,
        totalCount: Int,
        pageSize: Int,
        maxWindowSize: Int,
        currentCount: Int
    ) -> Range<Int> {
        if currentCount >= maxWindowSize {
            let lowerBound = max(0, current.lowerBound - pageSize)
            let upperBound = min(totalCount, lowerBound + currentCount)
            return lowerBound..<upperBound
        }
        return boundedRequestedRange(
            lowerBound: current.lowerBound - pageSize,
            upperBound: current.upperBound,
            totalCount: totalCount,
            anchorIndex: nil
        )
    }

    nonisolated static func nextForwardSearchRange(
        current: Range<Int>,
        totalCount: Int,
        pageSize: Int,
        maxWindowSize: Int,
        currentCount: Int
    ) -> Range<Int> {
        if currentCount >= maxWindowSize {
            let upperBound = min(totalCount, current.upperBound + pageSize)
            let lowerBound = max(0, upperBound - currentCount)
            return lowerBound..<upperBound
        }
        return boundedRequestedRange(
            lowerBound: current.lowerBound,
            upperBound: current.upperBound + pageSize,
            totalCount: totalCount,
            anchorIndex: nil
        )
    }




    struct ReactionSnapshot {
        let reactions: [TopicReactionState]
        let currentUserReaction: TopicReactionState?
        let likeCount: UInt32
    }





    func performWithTimeout<T>(
        _ seconds: Double,
        operation: String,
        _ body: @escaping () async throws -> T
    ) async throws -> T {
        let coordinator = FireTopicDetailTimeoutCoordinator<T>()
        do {
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    coordinator.start(
                        continuation: continuation,
                        seconds: seconds,
                        operation: operation,
                        body: body
                    )
                }
            } onCancel: {
                coordinator.cancel()
            }
        } catch let error as FireTopicDetailTimeoutError {
            if !Task.isCancelled {
                appViewModel.topicDetailLogger()?.error(
                    "topic detail fetch timed out operation=\(operation) seconds=\(seconds)"
                )
            }
            throw error
        } catch {
            throw error
        }
    }
}

private final class FireTopicDetailTimeoutCoordinator<T>: @unchecked Sendable {
    private let lock = NSLock()
    var continuation: CheckedContinuation<T, Error>?
    var workTask: Task<Void, Never>?
    var timeoutTask: Task<Void, Never>?

    func start(
        continuation: CheckedContinuation<T, Error>,
        seconds: Double,
        operation: String,
        body: @escaping () async throws -> T
    ) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()

        let workTask = Task { [weak self] in
            do {
                let value = try await body()
                self?.finish(.success(value), cancelWork: false, cancelTimeout: true)
            } catch {
                self?.finish(.failure(error), cancelWork: false, cancelTimeout: true)
            }
        }
        setWorkTask(workTask)

        let timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(seconds))
            } catch {
                return
            }
            self?.finish(
                .failure(FireTopicDetailTimeoutError(operation: operation, seconds: seconds)),
                cancelWork: true,
                cancelTimeout: false
            )
        }
        setTimeoutTask(timeoutTask)
    }

    func cancel() {
        finish(.failure(CancellationError()), cancelWork: true, cancelTimeout: true)
    }

    func setWorkTask(_ task: Task<Void, Never>) {
        lock.lock()
        if continuation == nil {
            lock.unlock()
            task.cancel()
            return
        }
        workTask = task
        lock.unlock()
    }

    func setTimeoutTask(_ task: Task<Void, Never>) {
        lock.lock()
        if continuation == nil {
            lock.unlock()
            task.cancel()
            return
        }
        timeoutTask = task
        lock.unlock()
    }

    @discardableResult
    func finish(
        _ result: Result<T, Error>,
        cancelWork: Bool,
        cancelTimeout: Bool
    ) -> Bool {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return false
        }
        self.continuation = nil
        let workTask = self.workTask
        let timeoutTask = self.timeoutTask
        self.workTask = nil
        self.timeoutTask = nil
        lock.unlock()

        if cancelWork {
            workTask?.cancel()
        }
        if cancelTimeout {
            timeoutTask?.cancel()
        }
        continuation.resume(with: result)
        return true
    }
}

struct FireTopicDetailTimeoutError: LocalizedError {
    let operation: String
    let seconds: Double
    var errorDescription: String? {
        "\(operation)超时（\(Int(seconds))s），请稍后重试"
    }
}
