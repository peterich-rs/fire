import Foundation

private enum FireTopicDetailSearchDirection {
    case backward
    case forward
}

private struct FireTopicDetailPagePayload {
    let sourceSnapshot: TopicDetailSourceSnapshotState
    let treePresentation: TopicTreePresentationState
}

private struct FireTopicDetailFeedContentToken: Equatable {
    let header: FireTopicDetailFeedHeaderToken
    let stream: [UInt64]
    let posts: [FireTopicPostContentToken]

    init(detail: TopicDetailState) {
        header = FireTopicDetailFeedHeaderToken(detail: detail)
        stream = detail.postStream.stream
        posts = detail.postStream.posts.map(FireTopicPostContentToken.init(post:))
    }
}

private struct FireTopicDetailFeedHeaderToken: Equatable {
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

private struct FireTopicDetailChromeContentToken: Equatable {
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

private struct FireTopicParticipantContentToken: Equatable {
    let userId: UInt64
    let username: String?
    let name: String?

    init(participant: TopicParticipantState) {
        userId = participant.userId
        username = participant.username
        name = participant.name
    }
}

private struct FireTopicPostContentToken: Equatable {
    let id: UInt64
    let username: String
    let name: String?
    let avatarTemplate: String?
    let cookedLength: Int
    let cookedChecksum: UInt64
    let rawLength: Int
    let rawChecksum: UInt64
    let postNumber: UInt32
    let postType: Int32
    let createdAt: String?
    let updatedAt: String?
    let likeCount: UInt32
    let replyCount: UInt32
    let replyToPostNumber: UInt32?
    let replyToUsername: String?
    let bookmarked: Bool
    let bookmarkId: UInt64?
    let bookmarkName: String?
    let bookmarkReminderAt: String?
    let reactions: [FireTopicReactionContentToken]
    let currentUserReaction: FireTopicReactionContentToken?
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
        cookedLength = post.cooked.utf8.count
        cookedChecksum = Self.checksum(post.cooked)
        rawLength = post.raw?.utf8.count ?? 0
        rawChecksum = post.raw.map(Self.checksum) ?? 0
        postNumber = post.postNumber
        postType = post.postType
        createdAt = post.createdAt
        updatedAt = post.updatedAt
        likeCount = post.likeCount
        replyCount = post.replyCount
        replyToPostNumber = post.replyToPostNumber
        replyToUsername = post.replyToUser?.username
        bookmarked = post.bookmarked
        bookmarkId = post.bookmarkId
        bookmarkName = post.bookmarkName
        bookmarkReminderAt = post.bookmarkReminderAt
        reactions = post.reactions.map(FireTopicReactionContentToken.init(reaction:))
        currentUserReaction = post.currentUserReaction.map(FireTopicReactionContentToken.init(reaction:))
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

private struct FireTopicReactionContentToken: Equatable {
    let id: String
    let kind: String?
    let count: UInt32
    let canUndo: Bool?

    init(reaction: TopicReactionState) {
        id = reaction.id
        kind = reaction.kind
        count = reaction.count
        canUndo = reaction.canUndo
    }
}

private struct FireTopicPollContentToken: Equatable {
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

private struct FireTopicPollOptionContentToken: Equatable {
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
    nonisolated private static let topicPostPageSize = 30
    nonisolated private static let topicDetailInitialBatchSize: UInt16 = 40
    nonisolated private static let topicDetailLoadMoreBatchSize: UInt16 = 40
    nonisolated private static let topicPostPrefetchThreshold = 10
    nonisolated private static let topicPostForwardExpansionSize = 60
    nonisolated private static let replyContextPostBatchSize = 20
    nonisolated private static let topicPostVisibleRangeDebounce = Duration.milliseconds(120)
    nonisolated private static let topicPostHydrationIterationLimit = 8

    @Published private(set) var topicDetails: [UInt64: TopicDetailState] = [:]
    @Published private(set) var topicRenderStates: [UInt64: FireTopicDetailRenderState] = [:]
    @Published private(set) var topicPresenceUsersByTopic: [UInt64: [TopicPresenceUserState]] = [:]
    @Published private(set) var loadingMoreTopicPostIDs: Set<UInt64> = []
    @Published private(set) var loadMoreTopicPostErrorsByTopicID: [UInt64: String] = [:]
    @Published private(set) var loadingTopicIDs: Set<UInt64> = []
    @Published private(set) var submittingReplyTopicIDs: Set<UInt64> = []
    @Published private(set) var mutatingPostIDs: Set<UInt64> = []
    @Published private(set) var postActionTypes: [PostActionTypeState] = []
    @Published private(set) var isLoadingPostActionTypes = false
    @Published private(set) var postRepliesByPostID: [UInt64: [TopicPostState]] = [:]
    @Published private(set) var postReplyHistoryByPostID: [UInt64: [TopicPostState]] = [:]
    @Published private(set) var postReplyContextErrorsByPostID: [UInt64: String] = [:]
    @Published private(set) var loadingPostReplyContextIDs: Set<UInt64> = []
    @Published private(set) var topicAiSummaries: [UInt64: TopicAiSummaryState] = [:]
    @Published private(set) var loadingTopicAiSummaryIDs: Set<UInt64> = []
    @Published private(set) var unavailableTopicAiSummaryIDs: Set<UInt64> = []
    @Published private(set) var topicAiSummaryErrorsByTopicID: [UInt64: String] = [:]
    @Published private(set) var topicCollectionRevisions: [UInt64: UInt64] = [:]
    @Published private(set) var topicChromeRevisions: [UInt64: UInt64] = [:]
    @Published private(set) var topicSidecarRevisions: [UInt64: UInt64] = [:]
    @Published private(set) var topicInteractionRevisions: [UInt64: UInt64] = [:]
    @Published private(set) var errorMessagesByTopicID: [UInt64: String] = [:]

    private let appViewModel: FireAppViewModel
    private var topicSourceSnapshots: [UInt64: TopicDetailSourceSnapshotState] = [:]
    private var topicDetailNoticesByTopic: [UInt64: FireTopicDetailStatusMessage] = [:]
    private var topicRecoverySlugsByTopic: [UInt64: String] = [:]
    private var topicTreePresentations: [UInt64: TopicTreePresentationState] = [:]
    private var topicSourceCursorsByTopic: [UInt64: TopicSourceCursorState] = [:]
    private var pendingTopicDetailRefreshTasks: [UInt64: Task<Void, Never>] = [:]
    private var topicPresenceHeartbeatTasks: [UInt64: Task<Void, Never>] = [:]
    private var topicPostPreloadTasks: [UInt64: Task<Void, Never>] = [:]
    private var topicVisibleRangeTasks: [UInt64: Task<Void, Never>] = [:]
    private var topicRenderTasks: [UInt64: Task<Void, Never>] = [:]
    private var topicWindowStates: [UInt64: FireTopicDetailWindowState] = [:]
    private var topicRenderCaches: [UInt64: FireTopicDetailRenderCache] = [:]
    private var topicRenderGenerations: [UInt64: UInt64] = [:]
    private var topicPostLookups: [UInt64: [UInt64: TopicPostState]] = [:]
    private var topicDetailFeedContentTokens: [UInt64: FireTopicDetailFeedContentToken] = [:]
    private var topicDetailChromeContentTokens: [UInt64: FireTopicDetailChromeContentToken] = [:]
    private var topicScrollInteractionStates: [UInt64: Bool] = [:]
    private var deferredTopicDetailRefreshTopicIDs: Set<UInt64> = []
    private var deferredTopicDetailRefreshPayloads: [UInt64: FireTopicDetailPagePayload] = [:]
    private var hydratingTopicPostIDs: Set<UInt64> = []
    private var pendingVisiblePostNumbersByTopic: [UInt64: Set<UInt32>] = [:]
    private var topicDetailTargetPostNumbers: [UInt64: UInt32] = [:]
    private var activeTopicDetailOwnerTokens: [UInt64: Set<String>] = [:]
    private var topicAiSummaryTasks: [UInt64: Task<Void, Never>] = [:]
    private var hasLoadedPostActionTypes = false

    init(appViewModel: FireAppViewModel) {
        self.appViewModel = appViewModel
    }

    private var renderBaseURLString: String {
        let trimmed = appViewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    private func bumpTopicCollectionRevision(topicId: UInt64) {
        topicCollectionRevisions[topicId, default: 0] &+= 1
    }

    private func bumpTopicChromeRevision(topicId: UInt64) {
        topicChromeRevisions[topicId, default: 0] &+= 1
    }

    private func bumpTopicSidecarRevision(topicId: UInt64) {
        topicSidecarRevisions[topicId, default: 0] &+= 1
    }

    private func bumpTopicInteractionRevision(topicId: UInt64) {
        topicInteractionRevisions[topicId, default: 0] &+= 1
    }

    private func setLoadingTopic(_ isLoading: Bool, topicId: UInt64) {
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

    private func setLoadingMoreTopicPosts(_ isLoading: Bool, topicId: UInt64) {
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

    private func setLoadMoreTopicPostsError(_ message: String?, topicId: UInt64) {
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

    private func setLoadingTopicAiSummary(_ isLoading: Bool, topicId: UInt64) {
        let changed: Bool
        if isLoading {
            changed = loadingTopicAiSummaryIDs.insert(topicId).inserted
        } else {
            changed = loadingTopicAiSummaryIDs.remove(topicId) != nil
        }
        if changed {
            bumpTopicSidecarRevision(topicId: topicId)
        }
    }

    private func setMutatingPost(
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

    private func setSubmittingReply(
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

    private func setLoadingPostReplyContext(
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

    private func setPostReplyContextError(
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

    private func setTopicPresenceUsers(
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

    private func setPendingScrollTarget(_ postNumber: UInt32?, topicId: UInt64) {
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

    private func updateTopicErrorMessage(_ message: String?, topicId: UInt64) {
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

    private func updateTopicDetailNotice(
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

    private func cancelInFlightFetches() {
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

    func loadTopicDetail(
        topicId: UInt64,
        topicSlug: String? = nil,
        targetPostNumber: UInt32? = nil,
        force: Bool = false
    ) async {
        rememberTopicRecoverySlug(topicSlug, topicId: topicId)
        if loadingTopicIDs.contains(topicId) {
            return
        }
        if !appViewModel.session.readiness.canReadAuthenticatedApi {
            applySession(appViewModel.session)
            return
        }

        if let targetPostNumber {
            setPendingScrollTarget(targetPostNumber, topicId: topicId)
        }

        var currentForce = force
        let allowsSuggestedUnreadRootScrollTarget = targetPostNumber == nil && topicDetails[topicId] == nil
        while true {
            if !currentForce,
               topicSourceSnapshots[topicId] != nil,
               targetPostNumber == nil || detailContainsPostNumber(topicId: topicId, postNumber: targetPostNumber) {
                updateTopicErrorMessage(nil, topicId: topicId)
                return
            }

            appViewModel.topicDetailLogger()?.debug(
                "loading topic detail source topic_id=\(topicId) force=\(currentForce) target_post=\(String(describing: targetPostNumber))"
            )
            do {
                setLoadingTopic(true, topicId: topicId)
                defer { setLoadingTopic(false, topicId: topicId) }
                let sessionStore = try await appViewModel.sessionStoreValue()
                updateTopicErrorMessage(nil, topicId: topicId)
                let payload = try await fetchTopicDetailPagePayload(
                    topicId: topicId,
                    targetPostNumber: targetPostNumber,
                    trackVisit: true,
                    forceLoad: currentForce || force,
                    allowsSuggestedUnreadRootScrollTarget: allowsSuggestedUnreadRootScrollTarget,
                    sessionStore: sessionStore,
                    tracksInitialLoadAPM: true
                )
                await applyTopicDetailPagePayload(
                    payload,
                    detailNotice: nil,
                    topicId: topicId,
                    allowsSuggestedUnreadRootScrollTarget: allowsSuggestedUnreadRootScrollTarget
                )
                appViewModel.topicDetailLogger()?.debug(
                    "loaded topic detail source topic_id=\(topicId) loaded_posts=\(payload.sourceSnapshot.loadedPosts.count) reply_rows=\(payload.treePresentation.replyRows.count) source_cursor_present=\(payload.sourceSnapshot.sourceCursor != nil)"
                )
                return
            } catch {
                appViewModel.topicDetailLogger()?.error(
                    "topic detail load failed topic_id=\(topicId) error=\(error.localizedDescription)"
                )
                if await appViewModel.attemptReadPathLoginRecovery(
                    operation: "加载话题详情",
                    error: error
                ) {
                    currentForce = true
                    continue
                }
                if !currentForce,
                   case FireUniFfiError.StaleSessionResponse = error {
                    appViewModel.topicDetailLogger()?.notice(
                        "retrying stale topic detail response topic_id=\(topicId)"
                    )
                    currentForce = true
                    continue
                }
                if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                    if topicDetails[topicId] == nil {
                        updateTopicErrorMessage(error.localizedDescription, topicId: topicId)
                    }
                    return
                }
                updateTopicErrorMessage(error.localizedDescription, topicId: topicId)
                return
            }
        }
    }

    private func fetchTopicDetailPagePayload(
        topicId: UInt64,
        targetPostNumber: UInt32?,
        trackVisit: Bool,
        forceLoad: Bool,
        allowsSuggestedUnreadRootScrollTarget: Bool = false,
        sessionStore: FireSessionStore,
        tracksInitialLoadAPM: Bool
    ) async throws -> FireTopicDetailPagePayload {
        let operation = tracksInitialLoadAPM ? "加载话题详情" : "刷新话题详情"
        let recoveryURL = topicCloudflareRecoveryURL(topicId: topicId)
        return try await performWithTimeout(30, operation: operation) { [appViewModel] in
            let fetchOperation = {
                try await appViewModel.performWithCloudflareRecovery(
                    operation: operation,
                    originURL: recoveryURL
                ) {
                    let fetchStartedAt = Date()
                    let page = try await sessionStore.fetchTopicDetailPage(
                        query: TopicDetailSourceQueryState(
                            topicId: topicId,
                            targetPostNumber: targetPostNumber,
                            allowSuggestedUnreadRoot: allowsSuggestedUnreadRootScrollTarget,
                            trackVisit: trackVisit,
                            forceLoad: forceLoad,
                            initialBatchSize: Self.topicDetailInitialBatchSize,
                            loadMoreBatchSize: Self.topicDetailLoadMoreBatchSize,
                            maxAutoBatchesPerGesture: 3,
                            maxAutoPostsPerGesture: 120
                        )
                    )
                    appViewModel.topicDetailLogger()?.debug(
                        "topic detail page ffi topic_id=\(topicId) ffi_page_ms=\(Self.elapsedMilliseconds(since: fetchStartedAt)) source_loaded_posts=\(page.sourceSnapshot.loadedPosts.count) body_post_included=true tree_total_loaded_post_count=\(page.treePresentation.totalLoadedPostCount) reply_rows=\(page.treePresentation.replyRows.count) cooked_byte_count=\(Self.cookedByteCount(sourceSnapshot: page.sourceSnapshot))"
                    )
                    return FireTopicDetailPagePayload(
                        sourceSnapshot: page.sourceSnapshot,
                        treePresentation: page.treePresentation
                    )
                }
            }
            if tracksInitialLoadAPM {
                return try await FireAPMManager.shared.withSpan(
                    .topicDetailInitialLoad,
                    metadata: ["topic_id": String(topicId)]
                ) {
                    try await fetchOperation()
                }
            }
            return try await fetchOperation()
        }
    }

    private func detailContainsPostNumber(topicId: UInt64, postNumber: UInt32?) -> Bool {
        guard let postNumber else { return true }
        return topicDetails[topicId]?.postStream.posts.contains(where: { $0.postNumber == postNumber }) == true
    }

    private func rememberTopicRecoverySlug(_ topicSlug: String?, topicId: UInt64) {
        let trimmedSlug = topicSlug?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedSlug.isEmpty else {
            return
        }
        topicRecoverySlugsByTopic[topicId] = trimmedSlug
    }

    private func bestKnownTopicRecoverySlug(topicId: UInt64) -> String? {
        let candidates = [
            topicSourceSnapshots[topicId]?.header.slug,
            topicDetails[topicId]?.slug,
            topicRecoverySlugsByTopic[topicId],
        ]
        for candidate in candidates {
            let trimmedSlug = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmedSlug.isEmpty {
                return trimmedSlug
            }
        }
        return nil
    }

    private func topicCloudflareRecoveryURL(topicId: UInt64) -> URL {
        appViewModel.cloudflareRecoveryTopicURL(
            topicId: topicId,
            topicSlug: bestKnownTopicRecoverySlug(topicId: topicId)
        )
    }

    private func synthesizedTopicDetail(
        sourceSnapshot: TopicDetailSourceSnapshotState,
        treePresentation: TopicTreePresentationState
    ) -> TopicDetailState {
        let replyRows = FireTopicPresentation
            .uniqueTreeRowsPreservingOrder(treePresentation.replyRows)
            .filter { row in
                row.postId != sourceSnapshot.body.post.id
            }
        let postsByID = FireTopicPresentation.topicPostsByID(
            [sourceSnapshot.body.post] + sourceSnapshot.loadedPosts
        )
        let posts = FireTopicPresentation.uniqueTopicPostsPreservingOrder(
            [sourceSnapshot.body.post] + replyRows.compactMap { postsByID[$0.postId] }
        )
        return TopicDetailState(
            id: sourceSnapshot.header.topicId,
            messageBusLastId: sourceSnapshot.header.messageBusLastId,
            title: sourceSnapshot.header.title,
            slug: sourceSnapshot.header.slug,
            postsCount: sourceSnapshot.header.postsCount,
            replyCount: sourceSnapshot.header.replyCount,
            categoryId: sourceSnapshot.header.categoryId,
            tags: sourceSnapshot.header.tags,
            views: sourceSnapshot.header.views,
            likeCount: sourceSnapshot.header.likeCount,
            createdAt: sourceSnapshot.header.createdAt,
            highestPostNumber: sourceSnapshot.header.highestPostNumber,
            lastReadPostNumber: sourceSnapshot.header.lastReadPostNumber,
            bookmarks: sourceSnapshot.header.bookmarks,
            bookmarked: sourceSnapshot.header.bookmarked,
            bookmarkId: sourceSnapshot.header.bookmarkId,
            bookmarkName: sourceSnapshot.header.bookmarkName,
            bookmarkReminderAt: sourceSnapshot.header.bookmarkReminderAt,
            acceptedAnswer: sourceSnapshot.header.acceptedAnswer,
            hasAcceptedAnswer: sourceSnapshot.header.hasAcceptedAnswer,
            canVote: sourceSnapshot.header.canVote,
            voteCount: sourceSnapshot.header.voteCount,
            userVoted: sourceSnapshot.header.userVoted,
            summarizable: sourceSnapshot.header.summarizable,
            hasCachedSummary: sourceSnapshot.header.hasCachedSummary,
            hasSummary: sourceSnapshot.header.hasSummary,
            archetype: sourceSnapshot.header.archetype,
            postStream: TopicPostStreamState(
                posts: posts,
                stream: posts.map(\.id)
            ),
            details: sourceSnapshot.header.details
        )
    }

    private func applyTopicDetailPagePayload(
        _ payload: FireTopicDetailPagePayload,
        detailNotice: FireTopicDetailStatusMessage?,
        topicId: UInt64,
        allowsSuggestedUnreadRootScrollTarget: Bool = false
    ) async {
        let applyStartedAt = Date()
        var treePresentation = payload.treePresentation
        treePresentation.replyRows = FireTopicPresentation
            .uniqueTreeRowsPreservingOrder(treePresentation.replyRows)
            .filter { $0.postId != payload.sourceSnapshot.body.post.id }
        if allowsSuggestedUnreadRootScrollTarget,
           let suggestedTarget = treePresentation.firstUnreadRootPostNumber,
           suggestedTarget > 1,
           topicDetailTargetPostNumbers[topicId] == nil {
            setPendingScrollTarget(suggestedTarget, topicId: topicId)
        }
        rememberTopicRecoverySlug(payload.sourceSnapshot.header.slug, topicId: topicId)
        updateTopicDetailNotice(detailNotice, topicId: topicId)
        topicSourceSnapshots[topicId] = payload.sourceSnapshot
        topicTreePresentations[topicId] = treePresentation
        if let cursor = payload.sourceSnapshot.sourceCursor {
            topicSourceCursorsByTopic[topicId] = cursor
        } else {
            topicSourceCursorsByTopic.removeValue(forKey: topicId)
        }
        setLoadMoreTopicPostsError(nil, topicId: topicId)
        let detail = rebuildTopicDetail(
            sourceSnapshot: payload.sourceSnapshot,
            treePresentation: treePresentation,
            topicId: topicId
        )
        appViewModel.topicDetailLogger()?.debug(
            "topic detail page main apply topic_id=\(topicId) main_apply_ms=\(Self.elapsedMilliseconds(since: applyStartedAt)) source_loaded_posts=\(payload.sourceSnapshot.loadedPosts.count) body_post_included=true tree_total_loaded_post_count=\(treePresentation.totalLoadedPostCount) reply_rows=\(treePresentation.replyRows.count) cooked_byte_count=\(Self.cookedByteCount(sourceSnapshot: payload.sourceSnapshot))"
        )
        _ = await buildTopicDetailRenderUpdate(detail: detail, topicId: topicId)
        appViewModel.patchHomeTopicCounts(from: detail)
        loadTopicAiSummaryIfNeeded(topicId: topicId, detail: detail)
    }

    private func loadNextTopicSourcePage(
        topicId: UInt64,
        cursor: TopicSourceCursorState
    ) async {
        guard let sessionStore = try? await appViewModel.sessionStoreValue() else {
            return
        }

        do {
            let outcome = try await appViewModel.performWithCloudflareRecovery(
                operation: "加载更多帖子",
                originURL: topicCloudflareRecoveryURL(topicId: topicId)
            ) {
                try await sessionStore.loadMoreTopicPosts(
                    query: LoadMoreTopicPostsQueryState(cursor: cursor)
                )
            }
            guard topicSourceCursorsByTopic[topicId] == cursor else {
                return
            }

            setLoadMoreTopicPostsError(nil, topicId: topicId)
            await applyTopicDetailPagePayload(
                FireTopicDetailPagePayload(
                    sourceSnapshot: outcome.sourceSnapshot,
                    treePresentation: outcome.treePresentation
                ),
                detailNotice: nil,
                topicId: topicId
            )
        } catch {
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                return
            }
            setLoadMoreTopicPostsError(error.localizedDescription, topicId: topicId)
        }
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

    @discardableResult
    func loadMoreTopicPostsIfNeeded(topicId: UInt64) -> Bool {
        enqueueNextTopicSourcePageLoad(topicId: topicId)
    }

    @discardableResult
    private func enqueueNextTopicSourcePageLoad(topicId: UInt64) -> Bool {
        guard let cursor = topicSourceCursorsByTopic[topicId] else {
            return false
        }
        guard Self.canStartNextTopicSourcePageLoad(
            hasMoreTopicPosts: true,
            isLoadingMoreTopicPosts: loadingMoreTopicPostIDs.contains(topicId),
            hasPendingPreloadTask: topicPostPreloadTasks[topicId] != nil,
            hasLoadedDetail: topicDetails[topicId] != nil
        ) else { return false }

        setLoadMoreTopicPostsError(nil, topicId: topicId)
        setLoadingMoreTopicPosts(true, topicId: topicId)
        topicPostPreloadTasks[topicId] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.topicPostPreloadTasks[topicId] = nil
                self.setLoadingMoreTopicPosts(false, topicId: topicId)
            }
            await self.loadNextTopicSourcePage(topicId: topicId, cursor: cursor)
        }
        return true
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

    func handleVisiblePostNumbersChanged(
        topicId: UInt64,
        visiblePostNumbers: Set<UInt32>
    ) {
        guard !visiblePostNumbers.isEmpty else { return }

        guard topicWindowStates[topicId] != nil else {
            return
        }

        pendingVisiblePostNumbersByTopic[topicId] = visiblePostNumbers
        topicVisibleRangeTasks[topicId]?.cancel()
        topicVisibleRangeTasks[topicId] = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: Self.topicPostVisibleRangeDebounce)
            } catch {
                return
            }

            let latestVisiblePostNumbers =
                self.pendingVisiblePostNumbersByTopic.removeValue(forKey: topicId)
                ?? visiblePostNumbers
            self.topicVisibleRangeTasks[topicId] = nil
            await self.expandRequestedRangeIfNeeded(
                topicId: topicId,
                visiblePostNumbers: latestVisiblePostNumbers
            )
        }
    }

    func needsAnchoredReload(
        detail: TopicDetailState?,
        anchorPostNumber: UInt32?,
        window: FireTopicDetailWindowState?
    ) -> Bool {
        guard let anchorPostNumber else { return detail == nil }
        guard detail != nil, let window else { return true }
        return !window.loadedPostNumbers.contains(anchorPostNumber)
    }

    func beginTopicDetailLifecycle(topicId: UInt64, ownerToken: String) {
        var owners = activeTopicDetailOwnerTokens[topicId] ?? []
        let inserted = owners.insert(ownerToken).inserted
        activeTopicDetailOwnerTokens[topicId] = owners
        guard inserted else { return }

        appViewModel.topicDetailLogger()?.debug(
            "registered topic detail lifecycle topic_id=\(topicId) owner_token=\(ownerToken) owner_count=\(owners.count)"
        )
    }

    func endTopicDetailLifecycle(
        topicId: UInt64,
        ownerToken: String,
        visibleTopicIDs: Set<UInt64>
    ) {
        guard var owners = activeTopicDetailOwnerTokens[topicId] else { return }
        guard owners.remove(ownerToken) != nil else { return }

        if owners.isEmpty {
            activeTopicDetailOwnerTokens.removeValue(forKey: topicId)
        } else {
            activeTopicDetailOwnerTokens[topicId] = owners
        }

        appViewModel.topicDetailLogger()?.debug(
            "released topic detail lifecycle topic_id=\(topicId) owner_token=\(ownerToken) owner_count=\(owners.count)"
        )

        guard owners.isEmpty else { return }
        topicDetailTargetPostNumbers.removeValue(forKey: topicId)
        guard !visibleTopicIDs.contains(topicId) else { return }
        evictTopicDetailState(topicId: topicId, reason: "detail view disappeared")
    }

    func pruneInactiveTopicDetailState(retainingVisibleTopicIDs visibleTopicIDs: Set<UInt64>) {
        let retainedTopicIDs = retainedTopicDetailIDs(visibleTopicIDs: visibleTopicIDs)
        pruneInactiveTopicDetailState(retaining: retainedTopicIDs, visibleTopicIDs: visibleTopicIDs)
    }

    func maintainTopicDetailSubscription(topicId: UInt64, ownerToken: String) async {
        guard appViewModel.session.readiness.canOpenMessageBus else { return }
        guard topicDetails[topicId] != nil else {
            appViewModel.topicDetailLogger()?.debug(
                "skipping topic detail subscription bootstrap topic_id=\(topicId) reason=detail not loaded"
            )
            return
        }

        guard let store = appViewModel.currentSessionStore() else { return }

        do {
            let lastMessageId = topicSourceSnapshots[topicId]?.header.messageBusLastId
                ?? topicDetails[topicId]?.messageBusLastId
            try await store.subscribeTopicDetailChannel(
                topicId: topicId,
                ownerToken: ownerToken,
                lastMessageId: lastMessageId
            )
            try await store.subscribeTopicReactionChannel(topicId: topicId, ownerToken: ownerToken)
            try await store.subscribeTopicPollsChannel(topicId: topicId, ownerToken: ownerToken)
        } catch {
            try? await store.unsubscribeTopicPollsChannel(topicId: topicId, ownerToken: ownerToken)
            try? await store.unsubscribeTopicReactionChannel(topicId: topicId, ownerToken: ownerToken)
            try? await store.unsubscribeTopicDetailChannel(topicId: topicId, ownerToken: ownerToken)
            return
        }

        do {
            let presence = try await store.bootstrapTopicReplyPresence(
                topicId: topicId,
                ownerToken: ownerToken
            )
            applyTopicPresenceState(presence)
        } catch {
            setTopicPresenceUsers([], topicId: topicId)
        }

        defer {
            Task {
                await self.endTopicReplyPresence(topicId: topicId)
                self.setTopicPresenceUsers([], topicId: topicId)
                try? await store.unsubscribeTopicReplyPresenceChannel(topicId: topicId, ownerToken: ownerToken)
                try? await store.unsubscribeTopicPollsChannel(topicId: topicId, ownerToken: ownerToken)
                try? await store.unsubscribeTopicReactionChannel(topicId: topicId, ownerToken: ownerToken)
                try? await store.unsubscribeTopicDetailChannel(topicId: topicId, ownerToken: ownerToken)
            }
        }

        await appViewModel.ensureMessageBusActiveIfPossible()

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(3600))
            } catch {
                break
            }
        }
    }

    func handleMessageBusEvent(_ event: MessageBusEventState) {
        switch event.kind {
        case .topicDetail, .topicReaction:
            guard let topicId = event.topicId else { return }
            guard topicDetails[topicId] != nil else { return }
            scheduleTopicDetailRefresh(topicId: topicId)
        case .presence:
            guard let topicId = event.topicId else { return }
            refreshTopicPresenceState(topicId: topicId)
        default:
            break
        }
    }

    func setTopicDetailScrollInteractionActive(
        _ isActive: Bool,
        topicId: UInt64,
        drainDeferredRefresh: Bool = true
    ) {
        let previous = topicScrollInteractionStates[topicId] ?? false
        if isActive {
            topicScrollInteractionStates[topicId] = true
        } else {
            topicScrollInteractionStates.removeValue(forKey: topicId)
        }
        guard previous != isActive, !isActive, drainDeferredRefresh else { return }

        if let deferredPayload = deferredTopicDetailRefreshPayloads.removeValue(forKey: topicId) {
            deferredTopicDetailRefreshTopicIDs.remove(topicId)
            Task { @MainActor [weak self] in
                await self?.applyTopicDetailPagePayload(
                    deferredPayload,
                    detailNotice: nil,
                    topicId: topicId
                )
            }
            return
        }

        guard deferredTopicDetailRefreshTopicIDs.remove(topicId) != nil,
              let store = appViewModel.currentSessionStore(),
              topicDetails[topicId] != nil else {
            return
        }

        Task { @MainActor [weak self] in
            await self?.refreshTopicDetailFromMessageBus(topicId: topicId, sessionStore: store)
        }
    }

    func beginTopicReplyPresence(topicId: UInt64) {
        guard appViewModel.session.readiness.canOpenMessageBus else { return }
        guard appViewModel.canStartAuthenticatedMutation else { return }
        guard topicPresenceHeartbeatTasks[topicId] == nil else { return }
        guard let store = appViewModel.currentSessionStore() else { return }

        topicPresenceHeartbeatTasks[topicId] = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await store.updateTopicReplyPresence(topicId: topicId, active: true)
                } catch {
                    return
                }

                guard let self else { return }
                guard self.topicPresenceHeartbeatTasks[topicId] != nil else { return }

                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    return
                }
            }
        }
    }

    func endTopicReplyPresence(topicId: UInt64) async {
        let task = topicPresenceHeartbeatTasks.removeValue(forKey: topicId)
        task?.cancel()
        guard let store = appViewModel.currentSessionStore() else { return }
        try? await store.updateTopicReplyPresence(topicId: topicId, active: false)
    }

    func isSubmittingReply(topicId: UInt64) -> Bool {
        submittingReplyTopicIDs.contains(topicId)
    }

    func isMutatingPost(postId: UInt64) -> Bool {
        mutatingPostIDs.contains(postId)
    }

    func submitReply(
        topicId: UInt64,
        raw: String,
        replyToPostNumber: UInt32?
    ) async throws {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FireTopicInteractionError.emptyReply
        }

        guard appViewModel.canStartAuthenticatedMutation else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        guard !submittingReplyTopicIDs.contains(topicId) else {
            return
        }

        setSubmittingReply(true, topicId: topicId)
        defer { setSubmittingReply(false, topicId: topicId) }

        do {
            let sessionStore = try await appViewModel.sessionStoreValue()
            updateTopicErrorMessage(nil, topicId: topicId)
            let createdReply = try await FireAPMManager.shared.withSpan(
                .topicReplySubmit,
                metadata: [
                    "topic_id": String(topicId),
                    "reply_to_post_number": replyToPostNumber.map(String.init) ?? "root"
                ]
            ) {
                try await appViewModel.performWriteWithCloudflareRetry(
                    originURL: topicCloudflareRecoveryURL(topicId: topicId)
                ) {
                    try await sessionStore.createReply(
                        topicID: topicId,
                        raw: trimmed,
                        replyToPostNumber: replyToPostNumber
                    )
                }
            }
            await appViewModel.syncSessionSnapshotIfAvailable(from: sessionStore)
            applyCreatedReply(createdReply, topicId: topicId)
            try? await refreshTopicDetailAfterMutation(topicId: topicId, sessionStore: sessionStore)
        } catch {
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                throw error
            }
            updateTopicErrorMessage(error.localizedDescription, topicId: topicId)
            throw error
        }
    }

    func updatePost(
        topicID: UInt64,
        postID: UInt64,
        raw: String,
        editReason: String? = nil
    ) async throws -> TopicPostState {
        let trimmedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRaw.isEmpty else {
            throw FireTopicInteractionError.emptyReply
        }

        guard appViewModel.canStartAuthenticatedMutation else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        if mutatingPostIDs.contains(postID) {
            let sessionStore = try await appViewModel.sessionStoreValue()
            return try await sessionStore.fetchPost(postID: postID)
        }

        setMutatingPost(true, topicId: topicID, postId: postID)
        defer { setMutatingPost(false, topicId: topicID, postId: postID) }

        do {
            let sessionStore = try await appViewModel.sessionStoreValue()
            updateTopicErrorMessage(nil, topicId: topicID)
            let updatedPost = try await appViewModel.performWriteWithCloudflareRetry(
                originURL: topicCloudflareRecoveryURL(topicId: topicID)
            ) {
                try await sessionStore.updatePost(
                    postID: postID,
                    raw: trimmedRaw,
                    editReason: editReason
                )
            }
            await appViewModel.syncSessionSnapshotIfAvailable(from: sessionStore)
            try? await refreshTopicDetailAfterMutation(topicId: topicID, sessionStore: sessionStore)
            await appViewModel.refreshHomeFeedIfPossible(force: false)
            return updatedPost
        } catch {
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                throw error
            }
            updateTopicErrorMessage(error.localizedDescription, topicId: topicID)
            throw error
        }
    }

    func deletePost(topicID: UInt64, postID: UInt64) async throws {
        try await performPostManagementMutation(topicID: topicID, postID: postID) { sessionStore in
            try await sessionStore.deletePost(postID: postID)
        }
    }

    func recoverPost(topicID: UInt64, postID: UInt64) async throws {
        try await performPostManagementMutation(topicID: topicID, postID: postID) { sessionStore in
            try await sessionStore.recoverPost(postID: postID)
        }
    }

    func flagPost(
        topicID: UInt64,
        postID: UInt64,
        flagTypeID: UInt32,
        message: String?
    ) async throws {
        let trimmedMessage = message?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try await performPostManagementMutation(topicID: topicID, postID: postID) { sessionStore in
            try await sessionStore.flagPost(
                postID: postID,
                flagTypeID: flagTypeID,
                message: trimmedMessage?.isEmpty == true ? nil : trimmedMessage
            )
        }
    }

    func loadPostActionTypesIfNeeded(force: Bool = false) async {
        if isLoadingPostActionTypes {
            return
        }
        if hasLoadedPostActionTypes && !force {
            return
        }

        isLoadingPostActionTypes = true
        defer { isLoadingPostActionTypes = false }

        guard let sessionStore = try? await appViewModel.sessionStoreValue() else {
            return
        }

        do {
            let types = try await appViewModel.performWithCloudflareRecovery(
                operation: "加载举报类型"
            ) {
                try await sessionStore.fetchPostActionTypes()
            }
            postActionTypes = types
            hasLoadedPostActionTypes = true
        } catch {
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                return
            }
            appViewModel.topicDetailLogger()?.warning(
                "failed to load post action types: \(error.localizedDescription)"
            )
            hasLoadedPostActionTypes = true
        }
    }

    func loadPostReplyContextIfNeeded(
        topicID: UInt64,
        post: TopicPostState,
        force: Bool = false
    ) async {
        guard force
            || postRepliesByPostID[post.id] == nil
            || postReplyHistoryByPostID[post.id] == nil else {
            return
        }
        guard !loadingPostReplyContextIDs.contains(post.id) else {
            return
        }
        setLoadingPostReplyContext(true, topicId: topicID, postId: post.id)
        setPostReplyContextError(nil, topicId: topicID, postId: post.id)
        defer { setLoadingPostReplyContext(false, topicId: topicID, postId: post.id) }

        guard let sessionStore = try? await appViewModel.sessionStoreValue() else {
            return
        }

        do {
            let recoveryURL = topicCloudflareRecoveryURL(topicId: topicID)
            let replies = try await appViewModel.performWithCloudflareRecovery(
                operation: "加载帖子回复",
                originURL: recoveryURL
            ) {
                try await self.fetchReplyContextReplies(
                    topicID: topicID,
                    post: post,
                    sessionStore: sessionStore
                )
            }
            let replyHistory = try await appViewModel.performWithCloudflareRecovery(
                operation: "加载回复来源",
                originURL: recoveryURL
            ) {
                post.replyToPostNumber != nil
                    ? try await sessionStore.fetchPostReplyHistory(postID: post.id)
                    : []
            }
            postRepliesByPostID[post.id] = replies
            postReplyHistoryByPostID[post.id] = replyHistory

            let refreshedPosts = replies + replyHistory
            if !refreshedPosts.isEmpty {
                if let replyRows = applyReplyContextRowsIfPossible(
                    topicId: topicID,
                    rootPost: post,
                    contextPosts: refreshedPosts
                ),
                   let sourceSnapshot = topicSourceSnapshots[topicID],
                   let treePresentation = topicTreePresentations[topicID] {
                    let detail = rebuildTopicDetail(
                        sourceSnapshot: sourceSnapshot,
                        treePresentation: treePresentation,
                        topicId: topicID
                    )
                    _ = replyRows
                    await buildTopicDetailRenderUpdate(detail: detail, topicId: topicID)
                } else {
                    await applyHydratedTopicPostsIfNeeded(
                        topicId: topicID,
                        posts: refreshedPosts,
                        exhaustedPostIDs: []
                    )
                }
            }
        } catch {
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                return
            }
            setPostReplyContextError(error.localizedDescription, topicId: topicID, postId: post.id)
        }
    }

    private func applyReplyContextRowsIfPossible(
        topicId: UInt64,
        rootPost: TopicPostState,
        contextPosts: [TopicPostState]
    ) -> [TopicTreeRowState]? {
        guard var treePresentation = topicTreePresentations[topicId],
              var sourceSnapshot = topicSourceSnapshots[topicId] else {
            return nil
        }

        let existingRows = treePresentation.replyRows
        let mergedRows = Self.mergeReplyContextTreeRows(
            existingRows: existingRows,
            bodyPostNumber: sourceSnapshot.body.post.postNumber,
            rootPost: rootPost,
            contextPosts: contextPosts
        )
        guard mergedRows != existingRows else {
            return nil
        }

        treePresentation.replyRows = mergedRows
        sourceSnapshot.loadedPosts = FireTopicPresentation.mergeTopicPosts(
            existing: sourceSnapshot.loadedPosts,
            incoming: contextPosts,
            orderedPostIDs: sourceSnapshot.rawStreamIds
        )
        topicTreePresentations[topicId] = treePresentation
        topicSourceSnapshots[topicId] = sourceSnapshot
        return mergedRows
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

    private func fetchReplyContextReplies(
        topicID: UInt64,
        post: TopicPostState,
        sessionStore: FireSessionStore
    ) async throws -> [TopicPostState] {
        guard post.replyCount > 0 else {
            return []
        }

        let replyIDs = orderedUniquePostIDs(
            try await sessionStore.fetchPostReplyIds(postID: post.id)
        )
        guard !replyIDs.isEmpty else {
            return []
        }

        var replies: [TopicPostState] = []
        var startIndex = 0
        while startIndex < replyIDs.count {
            let endIndex = min(startIndex + Self.replyContextPostBatchSize, replyIDs.count)
            let batchIDs = Array(replyIDs[startIndex..<endIndex])
            replies.append(
                contentsOf: try await sessionStore.fetchTopicPosts(
                    topicID: topicID,
                    postIDs: batchIDs
                )
            )
            startIndex = endIndex
        }
        return replies
    }

    private func orderedUniquePostIDs(_ ids: [UInt64]) -> [UInt64] {
        var seen: Set<UInt64> = []
        var result: [UInt64] = []
        for id in ids where id > 0 && !seen.contains(id) {
            seen.insert(id)
            result.append(id)
        }
        return result
    }

    func setPostLiked(
        topicId: UInt64,
        postId: UInt64,
        liked: Bool
    ) async throws {
        guard appViewModel.canStartAuthenticatedMutation else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        guard !mutatingPostIDs.contains(postId) else {
            return
        }

        setMutatingPost(true, topicId: topicId, postId: postId)
        defer { setMutatingPost(false, topicId: topicId, postId: postId) }

        do {
            let sessionStore = try await appViewModel.sessionStoreValue()
            updateTopicErrorMessage(nil, topicId: topicId)
            let update = try await appViewModel.performWriteWithCloudflareRetry(
                originURL: topicCloudflareRecoveryURL(topicId: topicId)
            ) {
                if liked {
                    try await sessionStore.likePost(postID: postId)
                } else {
                    try await sessionStore.unlikePost(postID: postId)
                }
            }
            await appViewModel.syncSessionSnapshotIfAvailable(from: sessionStore)
            if let update {
                applyPostReactionUpdate(topicId: topicId, postId: postId, update: update)
            } else {
                try? await refreshTopicDetailAfterMutation(topicId: topicId, sessionStore: sessionStore)
            }
        } catch {
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                throw error
            }
            updateTopicErrorMessage(error.localizedDescription, topicId: topicId)
            throw error
        }
    }

    func togglePostReaction(
        topicId: UInt64,
        postId: UInt64,
        reactionId: String
    ) async throws {
        let trimmedReactionID = reactionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReactionID.isEmpty else {
            return
        }

        guard appViewModel.canStartAuthenticatedMutation else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        guard !mutatingPostIDs.contains(postId) else {
            return
        }

        setMutatingPost(true, topicId: topicId, postId: postId)
        defer { setMutatingPost(false, topicId: topicId, postId: postId) }

        do {
            let sessionStore = try await appViewModel.sessionStoreValue()
            updateTopicErrorMessage(nil, topicId: topicId)
            let update = try await appViewModel.performWriteWithCloudflareRetry(
                originURL: topicCloudflareRecoveryURL(topicId: topicId)
            ) {
                try await sessionStore.togglePostReaction(
                    postID: postId,
                    reactionID: trimmedReactionID
                )
            }
            applyPostReactionUpdate(topicId: topicId, postId: postId, update: update)
        } catch {
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                throw error
            }
            updateTopicErrorMessage(error.localizedDescription, topicId: topicId)
            throw error
        }
    }

    private func performPostManagementMutation(
        topicID: UInt64,
        postID: UInt64,
        operation: @escaping (FireSessionStore) async throws -> Void
    ) async throws {
        guard appViewModel.canStartAuthenticatedMutation else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }
        guard !mutatingPostIDs.contains(postID) else {
            return
        }

        setMutatingPost(true, topicId: topicID, postId: postID)
        defer { setMutatingPost(false, topicId: topicID, postId: postID) }

        do {
            let sessionStore = try await appViewModel.sessionStoreValue()
            updateTopicErrorMessage(nil, topicId: topicID)
            try await appViewModel.performWriteWithCloudflareRetry(
                originURL: topicCloudflareRecoveryURL(topicId: topicID)
            ) {
                try await operation(sessionStore)
            }
            await appViewModel.syncSessionSnapshotIfAvailable(from: sessionStore)
            try? await refreshTopicDetailAfterMutation(topicId: topicID, sessionStore: sessionStore)
            await appViewModel.refreshHomeFeedIfPossible(force: false)
        } catch {
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                throw error
            }
            updateTopicErrorMessage(error.localizedDescription, topicId: topicID)
            throw error
        }
    }

    func refreshTopicDetailAfterMutation(topicId: UInt64) async {
        guard let sessionStore = try? await appViewModel.sessionStoreValue() else {
            return
        }
        try? await refreshTopicDetailAfterMutation(topicId: topicId, sessionStore: sessionStore)
    }

    private func refreshTopicDetailAfterMutation(
        topicId: UInt64,
        sessionStore: FireSessionStore
    ) async throws {
        let payload = try await fetchTopicDetailPagePayload(
            topicId: topicId,
            targetPostNumber: nil,
            trackVisit: false,
            forceLoad: false,
            sessionStore: sessionStore,
            tracksInitialLoadAPM: false
        )
        await applyTopicDetailPagePayload(
            payload,
            detailNotice: nil,
            topicId: topicId
        )
    }

    private func refreshTopicDetailPageFromNetwork(
        topicId: UInt64,
        targetPostNumber: UInt32?,
        sessionStore: FireSessionStore
    ) async throws -> FireTopicDetailPagePayload {
        try await fetchTopicDetailPagePayload(
            topicId: topicId,
            targetPostNumber: targetPostNumber,
            trackVisit: false,
            forceLoad: false,
            sessionStore: sessionStore,
            tracksInitialLoadAPM: false
        )
    }

    private func scheduleTopicDetailRefresh(topicId: UInt64) {
        pendingTopicDetailRefreshTasks[topicId]?.cancel()
        pendingTopicDetailRefreshTasks[topicId] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            guard let self, let store = self.appViewModel.currentSessionStore() else { return }
            await self.refreshTopicDetailFromMessageBus(topicId: topicId, sessionStore: store)
        }
    }

    private func refreshTopicDetailFromMessageBus(
        topicId: UInt64,
        sessionStore: FireSessionStore
    ) async {
        guard topicDetails[topicId] != nil else { return }
        if topicScrollInteractionStates[topicId] == true {
            deferredTopicDetailRefreshTopicIDs.insert(topicId)
            return
        }

        do {
            let payload = try await refreshTopicDetailPageFromNetwork(
                topicId: topicId,
                targetPostNumber: nil,
                sessionStore: sessionStore
            )
            guard topicDetails[topicId] != nil else { return }
            if topicScrollInteractionStates[topicId] == true {
                deferredTopicDetailRefreshPayloads[topicId] = payload
                deferredTopicDetailRefreshTopicIDs.insert(topicId)
                return
            }
            deferredTopicDetailRefreshTopicIDs.remove(topicId)
            deferredTopicDetailRefreshPayloads.removeValue(forKey: topicId)
            await applyTopicDetailPagePayload(
                payload,
                detailNotice: nil,
                topicId: topicId
            )
        } catch {
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                appViewModel.topicDetailLogger()?.notice(
                    "recoverable session error swallowed during topic detail refresh topic_id=\(topicId)"
                )
                return
            }
            appViewModel.topicDetailLogger()?.error(
                "topic detail background refresh failed topic_id=\(topicId) error=\(error.localizedDescription)"
            )
        }
    }

    private func refreshTopicPresenceState(topicId: UInt64) {
        guard let store = appViewModel.currentSessionStore() else { return }
        Task { [weak self] in
            guard let self else { return }
            guard let presence = try? await store.topicReplyPresenceState(topicId: topicId) else {
                return
            }
            self.applyTopicPresenceState(presence)
        }
    }

    private func applyTopicPresenceState(_ state: TopicPresenceState) {
        let currentUserID = appViewModel.session.bootstrap.currentUserId
        let filteredUsers = state.users.filter { user in
            guard let currentUserID else { return true }
            return user.id != currentUserID
        }
        setTopicPresenceUsers(filteredUsers, topicId: state.topicId)
    }

    func retainedTopicDetailIDs(visibleTopicIDs: Set<UInt64>) -> Set<UInt64> {
        let activeTopicIDs = activeTopicDetailOwnerTokens.compactMap { topicId, owners in
            owners.isEmpty ? nil : topicId
        }
        return visibleTopicIDs.union(activeTopicIDs)
    }

    private func pruneInactiveTopicDetailState(
        retaining retainedTopicIDs: Set<UInt64>,
        visibleTopicIDs: Set<UInt64>
    ) {
        let trackedTopicIDs = Set(topicDetails.keys)
            .union(topicWindowStates.keys)
            .union(topicPresenceUsersByTopic.keys)
            .union(errorMessagesByTopicID.keys)
            .union(topicAiSummaries.keys)
            .union(loadingTopicAiSummaryIDs)
            .union(unavailableTopicAiSummaryIDs)
            .union(topicAiSummaryErrorsByTopicID.keys)
            .union(topicAiSummaryTasks.keys)
            .union(topicChromeRevisions.keys)
            .union(topicSidecarRevisions.keys)
            .union(topicInteractionRevisions.keys)
            .union(topicScrollInteractionStates.keys)
            .union(deferredTopicDetailRefreshTopicIDs)
            .union(deferredTopicDetailRefreshPayloads.keys)
            .union(loadingTopicIDs)
            .union(loadingMoreTopicPostIDs)
            .union(topicPostPreloadTasks.keys)
            .union(pendingTopicDetailRefreshTasks.keys)
            .union(topicPresenceHeartbeatTasks.keys)
        let inactiveTopicIDs = trackedTopicIDs.subtracting(retainedTopicIDs)
        guard !inactiveTopicIDs.isEmpty else {
            return
        }

        let activeTopicIDs = retainedTopicIDs.subtracting(visibleTopicIDs)
        appViewModel.topicDetailLogger()?.notice(
            "pruning inactive topic detail state retained_active_topic_ids=\(Self.formattedTopicIDs(activeTopicIDs)) pruned_topic_ids=\(Self.formattedTopicIDs(inactiveTopicIDs))"
        )

        for topicId in inactiveTopicIDs.sorted() {
            evictTopicDetailState(topicId: topicId, reason: "topic list refresh pruned inactive detail")
        }
    }

    private static func formattedTopicIDs(_ topicIDs: Set<UInt64>) -> String {
        topicIDs.sorted().map(String.init).joined(separator: ",")
    }

    private func activeAnchorPostNumber(topicId: UInt64) -> UInt32? {
        topicWindowStates[topicId]?.activeAnchorPostNumber
            ?? topicDetailTargetPostNumbers[topicId]
    }

    private func clearTransientAnchor(topicId: UInt64) {
        setPendingScrollTarget(nil, topicId: topicId)
        if let window = topicWindowStates[topicId] {
            topicWindowStates[topicId] = window.clearingTransientAnchor()
        }
    }

    private func evictTopicDetailState(topicId: UInt64, reason: String) {
        topicSourceSnapshots.removeValue(forKey: topicId)
        topicDetailNoticesByTopic.removeValue(forKey: topicId)
        topicRecoverySlugsByTopic.removeValue(forKey: topicId)
        topicTreePresentations.removeValue(forKey: topicId)
        topicSourceCursorsByTopic.removeValue(forKey: topicId)
        topicPostLookups.removeValue(forKey: topicId)
        pendingVisiblePostNumbersByTopic.removeValue(forKey: topicId)
        topicScrollInteractionStates.removeValue(forKey: topicId)
        deferredTopicDetailRefreshTopicIDs.remove(topicId)
        deferredTopicDetailRefreshPayloads.removeValue(forKey: topicId)
        topicDetailFeedContentTokens.removeValue(forKey: topicId)
        topicDetailChromeContentTokens.removeValue(forKey: topicId)
        let removedDetail = topicDetails.removeValue(forKey: topicId) != nil
        let removedRenderState = topicRenderStates.removeValue(forKey: topicId) != nil
        topicRenderCaches.removeValue(forKey: topicId)
        topicRenderGenerations.removeValue(forKey: topicId)
        let removedWindow = topicWindowStates.removeValue(forKey: topicId) != nil
        let removedPresence = topicPresenceUsersByTopic.removeValue(forKey: topicId) != nil
        let removedError = errorMessagesByTopicID.removeValue(forKey: topicId) != nil
        let removedAiSummary = topicAiSummaries.removeValue(forKey: topicId) != nil
        let removedAiSummaryUnavailable = unavailableTopicAiSummaryIDs.remove(topicId) != nil
        let removedAiSummaryError = topicAiSummaryErrorsByTopicID.removeValue(forKey: topicId) != nil
        topicCollectionRevisions.removeValue(forKey: topicId)
        topicChromeRevisions.removeValue(forKey: topicId)
        topicSidecarRevisions.removeValue(forKey: topicId)
        topicInteractionRevisions.removeValue(forKey: topicId)
        let removedLoadingTopic = loadingTopicIDs.remove(topicId) != nil
        let removedLoadingMore = loadingMoreTopicPostIDs.remove(topicId) != nil
        let removedLoadMoreError = loadMoreTopicPostErrorsByTopicID.removeValue(forKey: topicId) != nil
        let removedLoadingAiSummary = loadingTopicAiSummaryIDs.remove(topicId) != nil
        let refreshTask = pendingTopicDetailRefreshTasks.removeValue(forKey: topicId)
        let presenceTask = topicPresenceHeartbeatTasks.removeValue(forKey: topicId)
        let preloadTask = topicPostPreloadTasks.removeValue(forKey: topicId)
        let visibleRangeTask = topicVisibleRangeTasks.removeValue(forKey: topicId)
        let renderTask = topicRenderTasks.removeValue(forKey: topicId)
        let aiSummaryTask = topicAiSummaryTasks.removeValue(forKey: topicId)
        refreshTask?.cancel()
        presenceTask?.cancel()
        preloadTask?.cancel()
        visibleRangeTask?.cancel()
        renderTask?.cancel()
        aiSummaryTask?.cancel()

        guard removedDetail
            || removedRenderState
            || removedWindow
            || removedPresence
            || removedError
            || removedAiSummary
            || removedAiSummaryUnavailable
            || removedAiSummaryError
            || removedLoadingTopic
            || removedLoadingMore
            || removedLoadMoreError
            || removedLoadingAiSummary
            || refreshTask != nil
            || presenceTask != nil
            || preloadTask != nil
            || visibleRangeTask != nil
            || renderTask != nil
            || aiSummaryTask != nil
        else {
            return
        }

        appViewModel.topicDetailLogger()?.notice(
            "evicted topic detail state topic_id=\(topicId) reason=\(reason)"
        )
    }

    private func prepareTopicDetail(
        _ detail: TopicDetailState,
        topicId: UInt64
    ) -> TopicDetailState {
        var preparedDetail = detail
        let stream = FireTopicPresentation.uniqueTopicPostIDsPreservingOrder(detail.postStream.stream)
        preparedDetail.postStream = TopicPostStreamState(
            posts: FireTopicPresentation.mergeTopicPosts(
                existing: detail.postStream.posts,
                incoming: [],
                orderedPostIDs: stream
            ),
            stream: stream
        )
        topicPostLookups[topicId] = FireTopicPresentation.topicPostsByID(
            preparedDetail.postStream.posts
        )

        return preparedDetail
    }

    private func cacheTopicDetail(
        _ detail: TopicDetailState,
        topicId: UInt64
    ) -> TopicDetailState {
        let cachedDetail = prepareTopicDetail(detail, topicId: topicId)
        _ = setTopicDetail(cachedDetail, topicId: topicId)

        scheduleTopicRenderCacheUpdate(detail: cachedDetail, topicId: topicId)
        return cachedDetail
    }

    @discardableResult
    private func setTopicDetail(
        _ detail: TopicDetailState,
        topicId: UInt64,
        bumpRevision: Bool = true
    ) -> Bool {
        let feedToken = FireTopicDetailFeedContentToken(detail: detail)
        let chromeToken = FireTopicDetailChromeContentToken(detail: detail)
        let feedChanged = topicDetailFeedContentTokens[topicId] != feedToken
        let chromeChanged = topicDetailChromeContentTokens[topicId] != chromeToken
        let changed = feedChanged || chromeChanged
        if changed {
            topicDetails[topicId] = detail
            topicDetailFeedContentTokens[topicId] = feedToken
            topicDetailChromeContentTokens[topicId] = chromeToken
            if bumpRevision, feedChanged {
                bumpTopicCollectionRevision(topicId: topicId)
            }
            if chromeChanged {
                bumpTopicChromeRevision(topicId: topicId)
            }
        }
        return changed
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

    nonisolated private static func elapsedMilliseconds(since startedAt: Date) -> Int64 {
        Int64((Date().timeIntervalSince(startedAt) * 1_000).rounded())
    }

    nonisolated private static func cookedByteCount(sourceSnapshot: TopicDetailSourceSnapshotState) -> Int {
        var seenPostIDs = Set<UInt64>()
        var total = 0
        for post in [sourceSnapshot.body.post] + sourceSnapshot.loadedPosts {
            if seenPostIDs.insert(post.id).inserted {
                total += post.cooked.utf8.count
            }
        }
        return total
    }

    private func rebuildTopicDetail(
        sourceSnapshot: TopicDetailSourceSnapshotState,
        treePresentation: TopicTreePresentationState,
        topicId: UInt64
    ) -> TopicDetailState {
        let detail = synthesizedTopicDetail(
            sourceSnapshot: sourceSnapshot,
            treePresentation: treePresentation
        )
        topicPostLookups[topicId] = FireTopicPresentation.topicPostsByID(
            detail.postStream.posts
        )

        return detail
    }

    @discardableResult
    private func buildTopicDetailRenderUpdate(
        detail: TopicDetailState,
        topicId: UInt64
    ) async -> TopicDetailState {
        let cachedDetail = prepareTopicDetail(detail, topicId: topicId)
        let previousRenderCache = topicRenderCaches[topicId]
        let baseURLString = renderBaseURLString
        let generation = topicRenderGenerations[topicId, default: 0] &+ 1
        topicRenderGenerations[topicId] = generation

        topicRenderTasks[topicId]?.cancel()
        let renderTask = Task { [weak self] in
            let renderResult = await Task.detached(priority: .userInitiated) {
                let renderStartedAt = Date()
                let renderCache = FireTopicPresentation.detailRenderCache(
                    from: cachedDetail,
                    baseURLString: baseURLString,
                    previous: previousRenderCache
                )
                return (
                    renderCache: renderCache,
                    renderCacheMs: Self.elapsedMilliseconds(since: renderStartedAt)
                )
            }.value

            guard !Task.isCancelled else {
                return
            }

            await self?.applyTopicDetailRenderUpdate(
                detail: cachedDetail,
                renderCache: renderResult.renderCache,
                renderCacheMs: renderResult.renderCacheMs,
                topicId: topicId,
                generation: generation
            )
        }

        topicRenderTasks[topicId] = renderTask
        await renderTask.value
        return cachedDetail
    }

    private func applyTopicDetailRenderUpdate(
        detail: TopicDetailState,
        renderCache: FireTopicDetailRenderCache,
        renderCacheMs: Int64,
        topicId: UInt64,
        generation: UInt64
    ) {
        guard topicRenderGenerations[topicId] == generation else {
            return
        }

        topicRenderTasks[topicId] = nil

        let previousRenderCache = topicRenderCaches[topicId]
        let didUpdateDetail = setTopicDetail(
            detail,
            topicId: topicId,
            bumpRevision: false
        )
        let didRepairRenderState = !Self.renderStateCoversRowInputs(
            topicRenderStates[topicId],
            rowInputs: renderCache.rowInputs,
            originalPostID: renderCache.rowInputs.first?.postID
        ) && Self.renderStateCoversRowInputs(
            renderCache.renderState,
            rowInputs: renderCache.rowInputs,
            originalPostID: renderCache.rowInputs.first?.postID
        )
        let didUpdateRenderState =
            previousRenderCache?.baseURLString != renderCache.baseURLString
            || previousRenderCache?.rowInputs != renderCache.rowInputs
            || previousRenderCache?.contentInputsByPostID != renderCache.contentInputsByPostID
            || didRepairRenderState

        topicRenderCaches[topicId] = renderCache
        if didUpdateRenderState {
            topicRenderStates[topicId] = renderCache.renderState
        }
        if didUpdateDetail || didUpdateRenderState {
            bumpTopicCollectionRevision(topicId: topicId)
        }
        appViewModel.topicDetailLogger()?.debug(
            "topic detail render cache topic_id=\(topicId) render_cache_ms=\(renderCacheMs) row_input_count=\(renderCache.rowInputs.count) content_input_count=\(renderCache.contentInputsByPostID.count) did_update_detail=\(didUpdateDetail) did_update_render_state=\(didUpdateRenderState)"
        )
    }

    private func scheduleTopicRenderCacheUpdate(
        detail: TopicDetailState,
        topicId: UInt64
    ) {
        let previousRenderCache = topicRenderCaches[topicId]
        let baseURLString = renderBaseURLString
        let generation = topicRenderGenerations[topicId, default: 0] &+ 1
        topicRenderGenerations[topicId] = generation

        topicRenderTasks[topicId]?.cancel()
        topicRenderTasks[topicId] = Task { [weak self] in
            let renderResult = await Task.detached(priority: .userInitiated) {
                let renderStartedAt = Date()
                let renderCache = FireTopicPresentation.detailRenderCache(
                    from: detail,
                    baseURLString: baseURLString,
                    previous: previousRenderCache
                )
                return (
                    renderCache: renderCache,
                    renderCacheMs: Self.elapsedMilliseconds(since: renderStartedAt)
                )
            }.value

            guard !Task.isCancelled else {
                return
            }

            await self?.applyTopicRenderCache(
                renderResult.renderCache,
                renderCacheMs: renderResult.renderCacheMs,
                topicId: topicId,
                generation: generation
            )
        }
    }

    private func applyTopicRenderCache(
        _ renderCache: FireTopicDetailRenderCache,
        renderCacheMs: Int64,
        topicId: UInt64,
        generation: UInt64
    ) {
        guard topicRenderGenerations[topicId] == generation else {
            return
        }

        topicRenderTasks[topicId] = nil

        let previousRenderCache = topicRenderCaches[topicId]
        topicRenderCaches[topicId] = renderCache

        let didRepairRenderState = !Self.renderStateCoversRowInputs(
            topicRenderStates[topicId],
            rowInputs: renderCache.rowInputs,
            originalPostID: renderCache.rowInputs.first?.postID
        ) && Self.renderStateCoversRowInputs(
            renderCache.renderState,
            rowInputs: renderCache.rowInputs,
            originalPostID: renderCache.rowInputs.first?.postID
        )
        let didUpdateRenderState =
            previousRenderCache?.baseURLString != renderCache.baseURLString
            || previousRenderCache?.rowInputs != renderCache.rowInputs
            || previousRenderCache?.contentInputsByPostID != renderCache.contentInputsByPostID
            || didRepairRenderState
        if didUpdateRenderState {
            topicRenderStates[topicId] = renderCache.renderState
            bumpTopicCollectionRevision(topicId: topicId)
        }
        appViewModel.topicDetailLogger()?.debug(
            "topic detail render cache topic_id=\(topicId) render_cache_ms=\(renderCacheMs) row_input_count=\(renderCache.rowInputs.count) content_input_count=\(renderCache.contentInputsByPostID.count) did_update_detail=false did_update_render_state=\(didUpdateRenderState)"
        )
    }

    private func applyTopicDetail(
        _ incomingDetail: TopicDetailState,
        topicId: UInt64,
        seededExhaustedPostIDs: Set<UInt64> = []
    ) {
        var detail = incomingDetail
        if let previousDetail = topicDetails[topicId] {
            detail.postStream.posts = FireTopicPresentation.mergeTopicPosts(
                existing: previousDetail.postStream.posts,
                incoming: detail.postStream.posts,
                orderedPostIDs: detail.postStream.stream
            )
        }
        detail = cacheTopicDetail(detail, topicId: topicId)

        refreshTopicWindowState(
            topicId: topicId,
            detail: detail,
            anchorPostNumber: activeAnchorPostNumber(topicId: topicId),
            requestedRange: topicWindowStates[topicId]?.requestedRange,
            pendingScrollTarget: topicWindowStates[topicId]?.pendingScrollTarget
                ?? topicDetailTargetPostNumbers[topicId]
        )

        if !seededExhaustedPostIDs.isEmpty {
            topicWindowStates[topicId]?.exhaustedPostIDs.formUnion(seededExhaustedPostIDs)
        }

        if hasMissingPostsInRequestedRange(topicId: topicId) {
            Task {
                await hydrateTopicPostsToTargetIfNeeded(topicId: topicId)
            }
        }

        loadTopicAiSummaryIfNeeded(topicId: topicId, detail: detail)
    }

    func reloadTopicAiSummary(topicId: UInt64) {
        guard let detail = topicDetails[topicId] else { return }
        loadTopicAiSummaryIfNeeded(topicId: topicId, detail: detail, force: true)
    }

    private func loadTopicAiSummaryIfNeeded(
        topicId: UInt64,
        detail: TopicDetailState,
        force: Bool = false
    ) {
        guard detail.summarizable || detail.hasCachedSummary || detail.hasSummary else {
            return
        }
        guard force
            || topicAiSummaries[topicId] == nil
                && !loadingTopicAiSummaryIDs.contains(topicId)
                && !unavailableTopicAiSummaryIDs.contains(topicId) else {
            return
        }

        topicAiSummaryTasks[topicId]?.cancel()
        let clearedUnavailable = unavailableTopicAiSummaryIDs.remove(topicId) != nil
        let clearedError = topicAiSummaryErrorsByTopicID.removeValue(forKey: topicId) != nil
        setLoadingTopicAiSummary(true, topicId: topicId)
        if clearedUnavailable || clearedError {
            bumpTopicSidecarRevision(topicId: topicId)
        }

        topicAiSummaryTasks[topicId] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.setLoadingTopicAiSummary(false, topicId: topicId)
                self.topicAiSummaryTasks.removeValue(forKey: topicId)
            }

            do {
                let sessionStore = try await self.appViewModel.sessionStoreValue()
                let summary = try await self.appViewModel.performWithCloudflareRecovery(
                    operation: "加载 AI 摘要",
                    originURL: self.topicCloudflareRecoveryURL(topicId: topicId)
                ) {
                    try await sessionStore.fetchTopicAiSummary(
                        topicID: topicId,
                        skipAgeCheck: false
                    )
                }

                if let summary,
                   !summary.summarizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let didChangeSummary = self.topicAiSummaries[topicId] != summary
                    self.topicAiSummaries[topicId] = summary
                    let clearedUnavailable = self.unavailableTopicAiSummaryIDs.remove(topicId) != nil
                    let clearedError = self.topicAiSummaryErrorsByTopicID.removeValue(forKey: topicId) != nil
                    if didChangeSummary || clearedUnavailable || clearedError {
                        self.bumpTopicSidecarRevision(topicId: topicId)
                    }
                } else {
                    let removedSummary = self.topicAiSummaries.removeValue(forKey: topicId) != nil
                    let insertedUnavailable = self.unavailableTopicAiSummaryIDs.insert(topicId).inserted
                    if removedSummary || insertedUnavailable {
                        self.bumpTopicSidecarRevision(topicId: topicId)
                    }
                }
            } catch {
                if await self.appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                    self.appViewModel.topicDetailLogger()?.notice(
                        "recoverable session error swallowed during topic AI summary load topic_id=\(topicId)"
                    )
                    return
                }
                if self.topicAiSummaryErrorsByTopicID[topicId] != error.localizedDescription {
                    self.topicAiSummaryErrorsByTopicID[topicId] = error.localizedDescription
                    self.bumpTopicSidecarRevision(topicId: topicId)
                }
                self.appViewModel.topicDetailLogger()?.error(
                    "topic AI summary load failed topic_id=\(topicId) error=\(error.localizedDescription)"
                )
            }
        }
    }

    private func prehydrateAnchoredContextBeforeDisplayIfNeeded(
        detail: TopicDetailState,
        topicId: UInt64,
        anchorPostNumber: UInt32?,
        previousWindow: FireTopicDetailWindowState?,
        pendingScrollTarget: UInt32?,
        sessionStore: FireSessionStore
    ) async throws -> (detail: TopicDetailState, exhaustedPostIDs: Set<UInt64>) {
        guard anchorPostNumber != nil || pendingScrollTarget != nil else {
            return (detail, previousWindow?.exhaustedPostIDs ?? [])
        }

        let window = resolvedTopicWindowState(
            detail: detail,
            previousWindow: previousWindow,
            anchorPostNumber: anchorPostNumber,
            requestedRange: previousWindow?.requestedRange,
            pendingScrollTarget: pendingScrollTarget
        )
        let missingPostIDs = FireTopicPresentation.missingPostIDs(
            orderedPostIDs: detail.postStream.stream,
            in: window.requestedRange,
            loadedPostIDs: Set(detail.postStream.posts.map(\.id)),
            excluding: window.exhaustedPostIDs
        )
        guard !missingPostIDs.isEmpty else {
            return (detail, window.exhaustedPostIDs)
        }

        let recoveryURL = topicCloudflareRecoveryURL(topicId: topicId)
        return try await Self.hydrateRequestedRange(
            detail: detail,
            window: window
        ) { [appViewModel] batchPostIDs in
            try await appViewModel.performWithCloudflareRecovery(
                operation: "加载更多帖子",
                originURL: recoveryURL
            ) {
                try await sessionStore.fetchTopicPosts(
                    topicID: topicId,
                    postIDs: batchPostIDs
                )
            }
        }
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

    private func applyCreatedReply(_ reply: TopicPostState, topicId: UInt64) {
        guard var detail = topicDetails[topicId] else {
            return
        }

        let isNewPost = !detail.postStream.stream.contains(reply.id)
        if isNewPost {
            detail.postStream.stream.append(reply.id)
        }

        if let postIndex = detail.postStream.posts.firstIndex(where: { $0.id == reply.id }) {
            detail.postStream.posts[postIndex] = reply
        } else {
            detail.postStream.posts.append(reply)
        }

        if isNewPost {
            detail.postsCount = max(
                detail.postsCount + 1,
                UInt32(detail.postStream.stream.count)
            )
            detail.replyCount = max(
                detail.replyCount + 1,
                detail.postsCount > 0 ? detail.postsCount - 1 : 0
            )
        }
        detail.highestPostNumber = max(detail.highestPostNumber, reply.postNumber)
        detail.lastReadPostNumber = max(detail.lastReadPostNumber ?? 0, reply.postNumber)

        let previousStreamCount = detail.postStream.stream.count
        detail = cacheTopicDetail(detail, topicId: topicId)

        var requestedRange = topicWindowStates[topicId]?.requestedRange
        if let window = topicWindowStates[topicId],
           window.requestedRange.upperBound >= previousStreamCount {
            requestedRange = window.requestedRange.lowerBound..<detail.postStream.stream.count
        }

        refreshTopicWindowState(
            topicId: topicId,
            detail: detail,
            anchorPostNumber: activeAnchorPostNumber(topicId: topicId),
            requestedRange: requestedRange,
            pendingScrollTarget: topicWindowStates[topicId]?.pendingScrollTarget
        )
        appViewModel.patchHomeTopicCounts(from: detail)
    }

    private func expandRequestedRangeIfNeeded(
        topicId: UInt64,
        visiblePostNumbers: Set<UInt32>
    ) async {
        guard let detail = topicDetails[topicId],
              var window = topicWindowStates[topicId] else {
            return
        }

        let previousRange = window.requestedRange
        let visibleIndices = visiblePostNumbers.compactMap { postNumber in
            streamIndex(forPostNumber: postNumber, in: detail)
        }

        if let minVisibleIndex = visibleIndices.min(),
           let maxVisibleIndex = visibleIndices.max() {
            let shouldExpandBackward = window.requestedRange.lowerBound > 0
                && minVisibleIndex <= window.requestedRange.lowerBound + Self.topicPostPrefetchThreshold
            let shouldExpandForward = window.requestedRange.upperBound < detail.postStream.stream.count
                && maxVisibleIndex >= max(
                    window.requestedRange.lowerBound,
                    window.requestedRange.upperBound - Self.topicPostPrefetchThreshold - 1
                )

            if shouldExpandBackward || shouldExpandForward {
                window.requestedRange = Self.expandedRequestedRange(
                    current: window.requestedRange,
                    totalCount: detail.postStream.stream.count,
                    expandBackward: shouldExpandBackward,
                    expandForward: shouldExpandForward,
                    anchorIndex: streamIndex(forPostNumber: window.activeAnchorPostNumber, in: detail)
                )
                topicWindowStates[topicId] = window
            }
        }

        if topicWindowStates[topicId]?.requestedRange != previousRange
            || hasMissingPostsInRequestedRange(topicId: topicId) {
            await hydrateTopicPostsToTargetIfNeeded(topicId: topicId)
        }
    }

    private func hydrateTopicPostsToTargetIfNeeded(topicId: UInt64) async {
        guard let sessionStore = appViewModel.currentSessionStore() else {
            return
        }
        guard !Task.isCancelled else {
            return
        }
        guard !loadingMoreTopicPostIDs.contains(topicId) else {
            return
        }
        guard hydratingTopicPostIDs.insert(topicId).inserted else {
            return
        }
        defer { hydratingTopicPostIDs.remove(topicId) }

        await FireAPMManager.shared.withSpan(
            .topicDetailHydration,
            metadata: ["topic_id": String(topicId)]
        ) {
            var hydratedPosts: [TopicPostState] = []
            var hydratedPostIDs: Set<UInt64> = []
            var exhaustedPostIDs: Set<UInt64> = []
            var iterationCount = 0

            while !Task.isCancelled {
                iterationCount &+= 1
                if iterationCount > Self.topicPostHydrationIterationLimit {
                    if !hydratedPosts.isEmpty || !exhaustedPostIDs.isEmpty {
                        await applyHydratedTopicPostsIfNeeded(
                            topicId: topicId,
                            posts: hydratedPosts,
                            exhaustedPostIDs: exhaustedPostIDs
                        )
                    }
                    appViewModel.topicDetailLogger()?.warning(
                        "topic post hydration hit iteration limit topic_id=\(topicId) iterations=\(iterationCount - 1)"
                    )
                    return
                }

                guard let detail = topicDetails[topicId],
                      let window = topicWindowStates[topicId] else {
                    return
                }

                let missingPostIDs = FireTopicPresentation.missingPostIDs(
                    orderedPostIDs: detail.postStream.stream,
                    in: window.requestedRange,
                    loadedPostIDs: Set(detail.postStream.posts.map(\.id)).union(hydratedPostIDs),
                    excluding: window.exhaustedPostIDs.union(exhaustedPostIDs)
                )
                guard !missingPostIDs.isEmpty else {
                    if !hydratedPosts.isEmpty || !exhaustedPostIDs.isEmpty {
                        await applyHydratedTopicPostsIfNeeded(
                            topicId: topicId,
                            posts: hydratedPosts,
                            exhaustedPostIDs: exhaustedPostIDs
                        )
                        hydratedPosts.removeAll()
                        hydratedPostIDs.removeAll()
                        exhaustedPostIDs.removeAll()
                        continue
                    }
                    if advanceRequestedRangeTowardPendingScrollTargetIfNeeded(
                        topicId: topicId,
                        detail: detail,
                        window: window
                    ) {
                        continue
                    }
                    await applyHydratedTopicPostsIfNeeded(
                        topicId: topicId,
                        posts: hydratedPosts,
                        exhaustedPostIDs: exhaustedPostIDs
                    )
                    return
                }

                let batchPostIDs = Array(missingPostIDs.prefix(Self.topicPostPageSize))

                do {
                    let fetchedPosts = try await appViewModel.performWithCloudflareRecovery(
                        operation: "加载更多帖子",
                        originURL: topicCloudflareRecoveryURL(topicId: topicId)
                    ) {
                        try await sessionStore.fetchTopicPosts(
                            topicID: topicId,
                            postIDs: batchPostIDs
                        )
                    }
                    let returnedPostIDs = Set(fetchedPosts.map(\.id))
                    exhaustedPostIDs.formUnion(
                        batchPostIDs.filter { !returnedPostIDs.contains($0) }
                    )
                    hydratedPosts.append(contentsOf: fetchedPosts)
                    hydratedPostIDs.formUnion(returnedPostIDs)
                } catch {
                    await applyHydratedTopicPostsIfNeeded(
                        topicId: topicId,
                        posts: hydratedPosts,
                        exhaustedPostIDs: exhaustedPostIDs
                    )
                    if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                        return
                    }
                    updateTopicErrorMessage(error.localizedDescription, topicId: topicId)
                    return
                }
            }

            await applyHydratedTopicPostsIfNeeded(
                topicId: topicId,
                posts: hydratedPosts,
                exhaustedPostIDs: exhaustedPostIDs
            )
        }
    }

    private func advanceRequestedRangeTowardPendingScrollTargetIfNeeded(
        topicId: UInt64,
        detail: TopicDetailState,
        window: FireTopicDetailWindowState
    ) -> Bool {
        guard let target = window.pendingScrollTarget,
              !window.loadedPostNumbers.contains(target) else {
            return false
        }

        let loadedPostNumbersInWindow = loadedPostNumbers(
            in: window.requestedRange,
            detail: detail
        )
        guard let nextRange = Self.nextRequestedRangeForUnresolvedTarget(
            postNumber: target,
            current: window.requestedRange,
            totalCount: detail.postStream.stream.count,
            loadedPostNumbersInCurrentRange: loadedPostNumbersInWindow
        ), nextRange != window.requestedRange else {
            return false
        }

        topicWindowStates[topicId]?.requestedRange = nextRange
        return true
    }

    private func loadedPostNumbers(
        in range: Range<Int>,
        detail: TopicDetailState
    ) -> [UInt32] {
        let stream = FireTopicPresentation.uniqueTopicPostIDsPreservingOrder(detail.postStream.stream)
        let indexByPostID = Dictionary(
            stream.enumerated().map { index, postID in
                (postID, index)
            },
            uniquingKeysWith: { first, _ in first }
        )
        return detail.postStream.posts.compactMap { post in
            guard let index = indexByPostID[post.id],
                  range.contains(index) else {
                return nil
            }
            return post.postNumber
        }
    }

    private func applyHydratedTopicPostsIfNeeded(
        topicId: UInt64,
        posts: [TopicPostState],
        exhaustedPostIDs: Set<UInt64>
    ) async {
        guard !posts.isEmpty || !exhaustedPostIDs.isEmpty else {
            return
        }
        guard var currentDetail = topicDetails[topicId],
              let currentWindow = topicWindowStates[topicId] else {
            return
        }

        topicWindowStates[topicId]?.exhaustedPostIDs.formUnion(exhaustedPostIDs)

        guard !posts.isEmpty else {
            if let target = topicWindowStates[topicId]?.pendingScrollTarget,
               isScrollTargetExhausted(topicId: topicId, postNumber: target) {
                markScrollTargetSatisfied(topicId: topicId, postNumber: target)
            }
            return
        }

        currentDetail.postStream.posts = FireTopicPresentation.mergeTopicPosts(
            existing: currentDetail.postStream.posts,
            incoming: posts,
            orderedPostIDs: currentDetail.postStream.stream
        )
        let cachedDetail = await buildTopicDetailRenderUpdate(
            detail: currentDetail,
            topicId: topicId
        )

        refreshTopicWindowState(
            topicId: topicId,
            detail: cachedDetail,
            anchorPostNumber: currentWindow.activeAnchorPostNumber,
            requestedRange: currentWindow.requestedRange,
            pendingScrollTarget: currentWindow.pendingScrollTarget
        )

        if let target = topicWindowStates[topicId]?.pendingScrollTarget,
           isScrollTargetExhausted(topicId: topicId, postNumber: target) {
            markScrollTargetSatisfied(topicId: topicId, postNumber: target)
        }
    }

    private func hasMissingPostsInRequestedRange(topicId: UInt64) -> Bool {
        guard let detail = topicDetails[topicId],
              let window = topicWindowStates[topicId] else {
            return false
        }

        let missingPostIDs = FireTopicPresentation.missingPostIDs(
            orderedPostIDs: detail.postStream.stream,
            in: window.requestedRange,
            loadedPostIDs: Set(detail.postStream.posts.map(\.id)),
            excluding: window.exhaustedPostIDs
        )
        return !missingPostIDs.isEmpty
    }

    private func refreshTopicWindowState(
        topicId: UInt64,
        detail: TopicDetailState,
        anchorPostNumber: UInt32?,
        requestedRange: Range<Int>?,
        pendingScrollTarget: UInt32?
    ) {
        topicWindowStates[topicId] = resolvedTopicWindowState(
            detail: detail,
            previousWindow: topicWindowStates[topicId],
            anchorPostNumber: anchorPostNumber,
            requestedRange: requestedRange,
            pendingScrollTarget: pendingScrollTarget
        )
    }

    private func resolvedTopicWindowState(
        detail: TopicDetailState,
        previousWindow: FireTopicDetailWindowState?,
        anchorPostNumber: UInt32?,
        requestedRange: Range<Int>?,
        pendingScrollTarget: UInt32?
    ) -> FireTopicDetailWindowState {
        let loadedPostNumbers = Set(detail.postStream.posts.map(\.postNumber))
        let loadedPostIDs = Set(detail.postStream.posts.map(\.id))
        var loadedIndices = IndexSet()
        for (index, postID) in detail.postStream.stream.enumerated() {
            if loadedPostIDs.contains(postID) {
                loadedIndices.insert(index)
            }
        }

        let resolvedAnchor = pendingScrollTarget ?? anchorPostNumber ?? previousWindow?.pendingScrollTarget
        let anchorIndex = streamIndex(forPostNumber: resolvedAnchor, in: detail)
        let anchorChanged = resolvedAnchor != previousWindow?.activeAnchorPostNumber
        let resolvedRequestedRange = resolveRequestedRange(
            requestedRange,
            previousWindow: previousWindow,
            totalCount: detail.postStream.stream.count,
            anchorIndex: anchorIndex,
            loadedIndices: loadedIndices,
            anchorChanged: anchorChanged
        )

        return FireTopicDetailWindowState(
            anchorPostNumber: resolvedAnchor,
            requestedRange: resolvedRequestedRange,
            loadedIndices: loadedIndices,
            loadedPostNumbers: loadedPostNumbers,
            exhaustedPostIDs: previousWindow?.exhaustedPostIDs ?? [],
            pendingScrollTarget: pendingScrollTarget
        )
    }

    private func resolveRequestedRange(
        _ requestedRange: Range<Int>?,
        previousWindow: FireTopicDetailWindowState?,
        totalCount: Int,
        anchorIndex: Int?,
        loadedIndices: IndexSet,
        anchorChanged: Bool
    ) -> Range<Int> {
        guard totalCount > 0 else {
            return 0..<0
        }

        if let requestedRange {
            return clampedRequestedRange(
                requestedRange,
                totalCount: totalCount,
                anchorIndex: anchorIndex,
                loadedIndices: loadedIndices
            )
        }

        if let previousWindow, !anchorChanged {
            return clampedRequestedRange(
                previousWindow.requestedRange,
                totalCount: totalCount,
                anchorIndex: anchorIndex,
                loadedIndices: loadedIndices
            )
        }

        return Self.initialRequestedRange(
            totalCount: totalCount,
            anchorIndex: anchorIndex,
            loadedIndices: loadedIndices
        )
    }

    private func clampedRequestedRange(
        _ requestedRange: Range<Int>,
        totalCount: Int,
        anchorIndex: Int?,
        loadedIndices: IndexSet
    ) -> Range<Int> {
        let clamped = requestedRange.clamped(to: 0..<totalCount)
        guard !clamped.isEmpty else {
            return Self.initialRequestedRange(
                totalCount: totalCount,
                anchorIndex: anchorIndex,
                loadedIndices: loadedIndices
            )
        }

        if let anchorIndex, !clamped.contains(anchorIndex) {
            return Self.initialRequestedRange(
                totalCount: totalCount,
                anchorIndex: anchorIndex,
                loadedIndices: loadedIndices
            )
        }

        let lowerBound = min(clamped.lowerBound, loadedIndices.first ?? clamped.lowerBound)
        let upperBound = max(clamped.upperBound, (loadedIndices.last.map { $0 + 1 }) ?? clamped.upperBound)
        return Self.boundedRequestedRange(
            lowerBound: lowerBound,
            upperBound: upperBound,
            totalCount: totalCount,
            anchorIndex: anchorIndex
        )
    }

    private func streamIndex(forPostNumber postNumber: UInt32?, in detail: TopicDetailState) -> Int? {
        guard let postNumber,
              let postID = detail.postStream.posts.first(where: { $0.postNumber == postNumber })?.id else {
            return nil
        }
        return detail.postStream.stream.firstIndex(of: postID)
    }

    nonisolated static func scrollTargetIsExhausted(
        postNumber: UInt32,
        window: FireTopicDetailWindowState,
        orderedPostIDs: [UInt64],
        loadedPostIDs: Set<UInt64>
    ) -> Bool {
        if window.loadedPostNumbers.contains(postNumber) {
            return false
        }

        let hasMissingInWindow = !FireTopicPresentation.missingPostIDs(
            orderedPostIDs: orderedPostIDs,
            in: window.requestedRange,
            loadedPostIDs: loadedPostIDs,
            excluding: window.exhaustedPostIDs
        ).isEmpty
        if hasMissingInWindow {
            return false
        }

        let wholeStreamResolved = FireTopicPresentation.missingPostIDs(
            orderedPostIDs: orderedPostIDs,
            in: 0..<orderedPostIDs.count,
            loadedPostIDs: loadedPostIDs,
            excluding: window.exhaustedPostIDs
        ).isEmpty
        if window.activeAnchorPostNumber == postNumber && !wholeStreamResolved {
            return false
        }

        return true
    }

    nonisolated static func nextRequestedRangeForUnresolvedTarget(
        postNumber: UInt32,
        current: Range<Int>,
        totalCount: Int,
        loadedPostNumbersInCurrentRange: [UInt32]
    ) -> Range<Int>? {
        guard totalCount > 0 else {
            return nil
        }
        guard current.lowerBound > 0 || current.upperBound < totalCount else {
            return nil
        }

        let estimatedIndex = max(0, min(Int(postNumber) - 1, totalCount - 1))
        if !current.contains(estimatedIndex) {
            return boundedRequestedRange(
                lowerBound: estimatedIndex - (topicPostPageSize / 2),
                upperBound: estimatedIndex + (topicPostPageSize / 2) + 1,
                totalCount: totalCount,
                anchorIndex: nil
            )
        }

        let direction: FireTopicDetailSearchDirection
        if let maxLoadedPostNumber = loadedPostNumbersInCurrentRange.max(),
           postNumber > maxLoadedPostNumber {
            direction = .forward
        } else if let minLoadedPostNumber = loadedPostNumbersInCurrentRange.min(),
                  postNumber < minLoadedPostNumber {
            direction = .backward
        } else if totalCount - current.upperBound >= current.lowerBound {
            direction = .forward
        } else {
            direction = .backward
        }

        return nextDirectionalSearchRange(
            current: current,
            totalCount: totalCount,
            direction: direction
        )
    }

    private nonisolated static func nextDirectionalSearchRange(
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

    private nonisolated static func previousDirectionalSearchRange(
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

    private nonisolated static func nextForwardSearchRange(
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

    nonisolated static func initialRequestedRange(
        totalCount: Int,
        anchorIndex: Int?,
        loadedIndices: IndexSet
    ) -> Range<Int> {
        guard totalCount > 0 else {
            return 0..<0
        }

        let loadedLowerBound = loadedIndices.first ?? anchorIndex ?? 0
        let loadedUpperBound = (loadedIndices.last.map { $0 + 1 }) ?? min(totalCount, loadedLowerBound + 1)
        let desiredLowerBound: Int
        if let anchorIndex {
            desiredLowerBound = anchorIndex - (topicPostPageSize / 2)
        } else {
            desiredLowerBound = min(loadedLowerBound, loadedUpperBound - topicPostPageSize)
        }

        return boundedRequestedRange(
            lowerBound: min(desiredLowerBound, loadedLowerBound),
            upperBound: max(loadedUpperBound, loadedLowerBound + topicPostPageSize),
            totalCount: totalCount,
            anchorIndex: anchorIndex
        )
    }

    nonisolated static func expandedRequestedRange(
        current: Range<Int>,
        totalCount: Int,
        expandBackward: Bool,
        expandForward: Bool,
        anchorIndex: Int?
    ) -> Range<Int> {
        let lowerBound = expandBackward ? current.lowerBound - topicPostPageSize : current.lowerBound
        let upperBound = expandForward ? current.upperBound + topicPostForwardExpansionSize : current.upperBound
        return boundedRequestedRange(
            lowerBound: lowerBound,
            upperBound: upperBound,
            totalCount: totalCount,
            anchorIndex: anchorIndex
        )
    }

    nonisolated static func boundedRequestedRange(
        lowerBound: Int,
        upperBound: Int,
        totalCount: Int,
        anchorIndex: Int?
    ) -> Range<Int> {
        guard totalCount > 0 else {
            return 0..<0
        }

        var lowerBound = max(0, min(lowerBound, totalCount))
        var upperBound = max(lowerBound, min(upperBound, totalCount))
        if lowerBound == upperBound {
            upperBound = min(totalCount, lowerBound + 1)
        }

        if upperBound - lowerBound <= FireTopicDetailWindowState.maxWindowSize {
            return lowerBound..<upperBound
        }

        if let anchorIndex {
            let maxLowerBound = max(0, totalCount - FireTopicDetailWindowState.maxWindowSize)
            let minimumLowerBound = max(0, anchorIndex - FireTopicDetailWindowState.maxWindowSize + 1)
            let maximumLowerBound = min(anchorIndex, maxLowerBound)
            lowerBound = max(minimumLowerBound, min(maximumLowerBound, lowerBound))
            upperBound = min(totalCount, lowerBound + FireTopicDetailWindowState.maxWindowSize)
            lowerBound = max(0, upperBound - FireTopicDetailWindowState.maxWindowSize)
            return lowerBound..<upperBound
        }

        upperBound = min(totalCount, lowerBound + FireTopicDetailWindowState.maxWindowSize)
        lowerBound = max(0, upperBound - FireTopicDetailWindowState.maxWindowSize)
        return lowerBound..<upperBound
    }

    private func applyPostReactionUpdate(
        topicId: UInt64,
        postId: UInt64,
        update: PostReactionUpdateState
    ) {
        guard var detail = topicDetails[topicId] else {
            return
        }
        guard let postIndex = detail.postStream.posts.firstIndex(where: { $0.id == postId }) else {
            return
        }

        var post = detail.postStream.posts[postIndex]
        let previousHeartCount = post.reactions.first(where: { $0.id == "heart" })?.count
        let updatedHeartCount = update.reactions.first(where: { $0.id == "heart" })?.count

        post.reactions = update.reactions
        post.currentUserReaction = update.currentUserReaction

        if let updatedHeartCount {
            post.likeCount = updatedHeartCount
        } else if previousHeartCount != nil || post.currentUserReaction?.id == "heart" {
            post.likeCount = 0
        }

        detail.postStream.posts[postIndex] = post
        if var sourceSnapshot = topicSourceSnapshots[topicId] {
            if sourceSnapshot.body.post.id == postId {
                sourceSnapshot.body.post = post
            }
            if let loadedIndex = sourceSnapshot.loadedPosts.firstIndex(where: { $0.id == postId }) {
                sourceSnapshot.loadedPosts[loadedIndex] = post
            }
            topicSourceSnapshots[topicId] = sourceSnapshot
        }
        _ = cacheTopicDetail(detail, topicId: topicId)
    }

    private func performWithTimeout<T>(
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
    private var continuation: CheckedContinuation<T, Error>?
    private var workTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

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

    private func setWorkTask(_ task: Task<Void, Never>) {
        lock.lock()
        if continuation == nil {
            lock.unlock()
            task.cancel()
            return
        }
        workTask = task
        lock.unlock()
    }

    private func setTimeoutTask(_ task: Task<Void, Never>) {
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
    private func finish(
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
