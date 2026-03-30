#if FIRE_USE_UNIFFI_STUBS
import Foundation

public enum LoginPhaseState: String, Codable, Sendable {
    case anonymous
    case cookiesCaptured
    case bootstrapCaptured
    case ready
}

public struct PlatformCookieState: Codable, Hashable, Sendable {
    public var name: String
    public var value: String
    public var domain: String?
    public var path: String?

    public init(name: String, value: String, domain: String?, path: String?) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
    }
}

public struct CookieState: Codable, Sendable {
    public var tToken: String?
    public var forumSession: String?
    public var cfClearance: String?
    public var csrfToken: String?

    public init(
        tToken: String? = nil,
        forumSession: String? = nil,
        cfClearance: String? = nil,
        csrfToken: String? = nil
    ) {
        self.tToken = tToken
        self.forumSession = forumSession
        self.cfClearance = cfClearance
        self.csrfToken = csrfToken
    }
}

public struct BootstrapState: Codable, Sendable {
    public var baseUrl: String
    public var discourseBaseUri: String?
    public var sharedSessionKey: String?
    public var currentUsername: String?
    public var longPollingBaseUrl: String?
    public var turnstileSitekey: String?
    public var topicTrackingStateMeta: String?
    public var preloadedJson: String?
    public var hasPreloadedData: Bool
    public var categories: [TopicCategoryState]
    public var enabledReactionIds: [String]
    public var minPostLength: UInt32

    public init(
        baseUrl: String,
        discourseBaseUri: String? = nil,
        sharedSessionKey: String? = nil,
        currentUsername: String? = nil,
        longPollingBaseUrl: String? = nil,
        turnstileSitekey: String? = nil,
        topicTrackingStateMeta: String? = nil,
        preloadedJson: String? = nil,
        hasPreloadedData: Bool = false,
        categories: [TopicCategoryState] = [],
        enabledReactionIds: [String] = ["heart"],
        minPostLength: UInt32 = 1
    ) {
        self.baseUrl = baseUrl
        self.discourseBaseUri = discourseBaseUri
        self.sharedSessionKey = sharedSessionKey
        self.currentUsername = currentUsername
        self.longPollingBaseUrl = longPollingBaseUrl
        self.turnstileSitekey = turnstileSitekey
        self.topicTrackingStateMeta = topicTrackingStateMeta
        self.preloadedJson = preloadedJson
        self.hasPreloadedData = hasPreloadedData
        self.categories = categories
        self.enabledReactionIds = enabledReactionIds
        self.minPostLength = minPostLength
    }
}

public struct SessionReadinessState: Codable, Sendable {
    public var hasLoginCookie: Bool
    public var hasForumSession: Bool
    public var hasCloudflareClearance: Bool
    public var hasCsrfToken: Bool
    public var hasCurrentUser: Bool
    public var hasPreloadedData: Bool
    public var hasSharedSessionKey: Bool
    public var canReadAuthenticatedApi: Bool
    public var canWriteAuthenticatedApi: Bool
    public var canOpenMessageBus: Bool

    public init(
        hasLoginCookie: Bool = false,
        hasForumSession: Bool = false,
        hasCloudflareClearance: Bool = false,
        hasCsrfToken: Bool = false,
        hasCurrentUser: Bool = false,
        hasPreloadedData: Bool = false,
        hasSharedSessionKey: Bool = false,
        canReadAuthenticatedApi: Bool = false,
        canWriteAuthenticatedApi: Bool = false,
        canOpenMessageBus: Bool = false
    ) {
        self.hasLoginCookie = hasLoginCookie
        self.hasForumSession = hasForumSession
        self.hasCloudflareClearance = hasCloudflareClearance
        self.hasCsrfToken = hasCsrfToken
        self.hasCurrentUser = hasCurrentUser
        self.hasPreloadedData = hasPreloadedData
        self.hasSharedSessionKey = hasSharedSessionKey
        self.canReadAuthenticatedApi = canReadAuthenticatedApi
        self.canWriteAuthenticatedApi = canWriteAuthenticatedApi
        self.canOpenMessageBus = canOpenMessageBus
    }
}

public struct SessionState: Codable, Sendable {
    public var cookies: CookieState
    public var bootstrap: BootstrapState
    public var readiness: SessionReadinessState
    public var loginPhase: LoginPhaseState
    public var hasLoginSession: Bool
    public var profileDisplayName: String
    public var loginPhaseLabel: String

    public init(
        cookies: CookieState,
        bootstrap: BootstrapState,
        readiness: SessionReadinessState,
        loginPhase: LoginPhaseState,
        hasLoginSession: Bool,
        profileDisplayName: String,
        loginPhaseLabel: String
    ) {
        self.cookies = cookies
        self.bootstrap = bootstrap
        self.readiness = readiness
        self.loginPhase = loginPhase
        self.hasLoginSession = hasLoginSession
        self.profileDisplayName = profileDisplayName
        self.loginPhaseLabel = loginPhaseLabel
    }
}

public struct LoginSyncState: Sendable {
    public var currentUrl: String?
    public var username: String?
    public var csrfToken: String?
    public var homeHtml: String?
    public var cookies: [PlatformCookieState]

    public init(
        currentUrl: String?,
        username: String?,
        csrfToken: String?,
        homeHtml: String?,
        cookies: [PlatformCookieState]
    ) {
        self.currentUrl = currentUrl
        self.username = username
        self.csrfToken = csrfToken
        self.homeHtml = homeHtml
        self.cookies = cookies
    }
}

public enum TopicListKindState: String, Codable, Sendable {
    case latest
    case new
    case unread
    case unseen
    case hot
    case top
}

public struct TopicListQueryState: Sendable {
    public var kind: TopicListKindState
    public var page: UInt32?
    public var topicIds: [UInt64]
    public var order: String?
    public var ascending: Bool?

    public init(
        kind: TopicListKindState,
        page: UInt32?,
        topicIds: [UInt64],
        order: String?,
        ascending: Bool?
    ) {
        self.kind = kind
        self.page = page
        self.topicIds = topicIds
        self.order = order
        self.ascending = ascending
    }
}

public struct TopicUserState: Codable, Sendable {
    public var id: UInt64
    public var username: String
    public var avatarTemplate: String?

    public init(id: UInt64, username: String, avatarTemplate: String?) {
        self.id = id
        self.username = username
        self.avatarTemplate = avatarTemplate
    }
}

public struct TopicPosterState: Codable, Sendable {
    public var userId: UInt64
    public var description: String?
    public var extras: String?

    public init(userId: UInt64, description: String?, extras: String?) {
        self.userId = userId
        self.description = description
        self.extras = extras
    }
}

public struct TopicTagState: Codable, Sendable {
    public var id: UInt64?
    public var name: String
    public var slug: String?

    public init(id: UInt64?, name: String, slug: String?) {
        self.id = id
        self.name = name
        self.slug = slug
    }
}

public struct TopicCategoryState: Codable, Sendable {
    public var id: UInt64
    public var name: String
    public var slug: String
    public var parentCategoryId: UInt64?
    public var colorHex: String?
    public var textColorHex: String?

    public init(
        id: UInt64,
        name: String,
        slug: String,
        parentCategoryId: UInt64?,
        colorHex: String?,
        textColorHex: String?
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.parentCategoryId = parentCategoryId
        self.colorHex = colorHex
        self.textColorHex = textColorHex
    }
}

public struct TopicSummaryState: Codable, Sendable {
    public var id: UInt64
    public var title: String
    public var slug: String
    public var postsCount: UInt32
    public var replyCount: UInt32
    public var views: UInt32
    public var likeCount: UInt32
    public var excerpt: String?
    public var createdAt: String?
    public var lastPostedAt: String?
    public var lastPosterUsername: String?
    public var categoryId: UInt64?
    public var pinned: Bool
    public var visible: Bool
    public var closed: Bool
    public var archived: Bool
    public var tags: [TopicTagState]
    public var posters: [TopicPosterState]
    public var unseen: Bool
    public var unreadPosts: UInt32
    public var newPosts: UInt32
    public var lastReadPostNumber: UInt32?
    public var highestPostNumber: UInt32
    public var hasAcceptedAnswer: Bool
    public var canHaveAnswer: Bool

    public init(
        id: UInt64,
        title: String,
        slug: String,
        postsCount: UInt32,
        replyCount: UInt32,
        views: UInt32,
        likeCount: UInt32,
        excerpt: String?,
        createdAt: String?,
        lastPostedAt: String?,
        lastPosterUsername: String?,
        categoryId: UInt64?,
        pinned: Bool,
        visible: Bool,
        closed: Bool,
        archived: Bool,
        tags: [TopicTagState],
        posters: [TopicPosterState],
        unseen: Bool,
        unreadPosts: UInt32,
        newPosts: UInt32,
        lastReadPostNumber: UInt32?,
        highestPostNumber: UInt32,
        hasAcceptedAnswer: Bool,
        canHaveAnswer: Bool
    ) {
        self.id = id
        self.title = title
        self.slug = slug
        self.postsCount = postsCount
        self.replyCount = replyCount
        self.views = views
        self.likeCount = likeCount
        self.excerpt = excerpt
        self.createdAt = createdAt
        self.lastPostedAt = lastPostedAt
        self.lastPosterUsername = lastPosterUsername
        self.categoryId = categoryId
        self.pinned = pinned
        self.visible = visible
        self.closed = closed
        self.archived = archived
        self.tags = tags
        self.posters = posters
        self.unseen = unseen
        self.unreadPosts = unreadPosts
        self.newPosts = newPosts
        self.lastReadPostNumber = lastReadPostNumber
        self.highestPostNumber = highestPostNumber
        self.hasAcceptedAnswer = hasAcceptedAnswer
        self.canHaveAnswer = canHaveAnswer
    }
}

public struct TopicRowState: Codable, Sendable {
    public var topic: TopicSummaryState
    public var excerptText: String?
    public var originalPosterUsername: String?
    public var originalPosterAvatarTemplate: String?
    public var tagNames: [String]
    public var createdTimestampUnixMs: UInt64?
    public var activityTimestampUnixMs: UInt64?
    public var lastPosterUsername: String?

    public init(
        topic: TopicSummaryState,
        excerptText: String?,
        originalPosterUsername: String?,
        originalPosterAvatarTemplate: String?,
        tagNames: [String],
        createdTimestampUnixMs: UInt64?,
        activityTimestampUnixMs: UInt64?,
        lastPosterUsername: String?
    ) {
        self.topic = topic
        self.excerptText = excerptText
        self.originalPosterUsername = originalPosterUsername
        self.originalPosterAvatarTemplate = originalPosterAvatarTemplate
        self.tagNames = tagNames
        self.createdTimestampUnixMs = createdTimestampUnixMs
        self.activityTimestampUnixMs = activityTimestampUnixMs
        self.lastPosterUsername = lastPosterUsername
    }
}

public struct TopicListState: Codable, Sendable {
    public var topics: [TopicSummaryState]
    public var users: [TopicUserState]
    public var rows: [TopicRowState]
    public var moreTopicsUrl: String?
    public var nextPage: UInt32?

    public init(
        topics: [TopicSummaryState],
        users: [TopicUserState],
        rows: [TopicRowState] = [],
        moreTopicsUrl: String?,
        nextPage: UInt32? = nil
    ) {
        self.topics = topics
        self.users = users
        self.rows = rows
        self.moreTopicsUrl = moreTopicsUrl
        self.nextPage = nextPage
    }
}

public struct TopicDetailQueryState: Sendable {
    public var topicId: UInt64
    public var postNumber: UInt32?
    public var trackVisit: Bool
    public var filter: String?
    public var usernameFilters: String?
    public var filterTopLevelReplies: Bool

    public init(
        topicId: UInt64,
        postNumber: UInt32?,
        trackVisit: Bool,
        filter: String?,
        usernameFilters: String?,
        filterTopLevelReplies: Bool
    ) {
        self.topicId = topicId
        self.postNumber = postNumber
        self.trackVisit = trackVisit
        self.filter = filter
        self.usernameFilters = usernameFilters
        self.filterTopLevelReplies = filterTopLevelReplies
    }
}

public struct TopicReactionState: Codable, Sendable {
    public var id: String
    public var kind: String?
    public var count: UInt32
    public var canUndo: Bool?

    public init(id: String, kind: String?, count: UInt32, canUndo: Bool? = nil) {
        self.id = id
        self.kind = kind
        self.count = count
        self.canUndo = canUndo
    }
}

public struct TopicReplyRequestState: Sendable {
    public var topicId: UInt64
    public var raw: String
    public var replyToPostNumber: UInt32?

    public init(topicId: UInt64, raw: String, replyToPostNumber: UInt32?) {
        self.topicId = topicId
        self.raw = raw
        self.replyToPostNumber = replyToPostNumber
    }
}

public struct PostReactionUpdateState: Codable, Sendable {
    public var reactions: [TopicReactionState]
    public var currentUserReaction: TopicReactionState?

    public init(
        reactions: [TopicReactionState],
        currentUserReaction: TopicReactionState?
    ) {
        self.reactions = reactions
        self.currentUserReaction = currentUserReaction
    }
}

public struct TopicPostState: Codable, Sendable {
    public var id: UInt64
    public var username: String
    public var name: String?
    public var avatarTemplate: String?
    public var cooked: String
    public var postNumber: UInt32
    public var postType: Int32
    public var createdAt: String?
    public var updatedAt: String?
    public var likeCount: UInt32
    public var replyCount: UInt32
    public var replyToPostNumber: UInt32?
    public var bookmarked: Bool
    public var bookmarkId: UInt64?
    public var reactions: [TopicReactionState]
    public var currentUserReaction: TopicReactionState?
    public var acceptedAnswer: Bool
    public var canEdit: Bool
    public var canDelete: Bool
    public var canRecover: Bool
    public var hidden: Bool

    public init(
        id: UInt64,
        username: String,
        name: String?,
        avatarTemplate: String?,
        cooked: String,
        postNumber: UInt32,
        postType: Int32,
        createdAt: String?,
        updatedAt: String?,
        likeCount: UInt32,
        replyCount: UInt32,
        replyToPostNumber: UInt32?,
        bookmarked: Bool,
        bookmarkId: UInt64?,
        reactions: [TopicReactionState],
        currentUserReaction: TopicReactionState?,
        acceptedAnswer: Bool,
        canEdit: Bool,
        canDelete: Bool,
        canRecover: Bool,
        hidden: Bool
    ) {
        self.id = id
        self.username = username
        self.name = name
        self.avatarTemplate = avatarTemplate
        self.cooked = cooked
        self.postNumber = postNumber
        self.postType = postType
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.likeCount = likeCount
        self.replyCount = replyCount
        self.replyToPostNumber = replyToPostNumber
        self.bookmarked = bookmarked
        self.bookmarkId = bookmarkId
        self.reactions = reactions
        self.currentUserReaction = currentUserReaction
        self.acceptedAnswer = acceptedAnswer
        self.canEdit = canEdit
        self.canDelete = canDelete
        self.canRecover = canRecover
        self.hidden = hidden
    }
}

public struct TopicPostStreamState: Codable, Sendable {
    public var posts: [TopicPostState]
    public var stream: [UInt64]

    public init(posts: [TopicPostState], stream: [UInt64]) {
        self.posts = posts
        self.stream = stream
    }
}

public struct TopicThreadReplyState: Codable, Sendable {
    public var postNumber: UInt32
    public var depth: UInt32
    public var parentPostNumber: UInt32?

    public init(postNumber: UInt32, depth: UInt32, parentPostNumber: UInt32?) {
        self.postNumber = postNumber
        self.depth = depth
        self.parentPostNumber = parentPostNumber
    }
}

public struct TopicThreadSectionState: Codable, Sendable {
    public var anchorPostNumber: UInt32
    public var replies: [TopicThreadReplyState]

    public init(anchorPostNumber: UInt32, replies: [TopicThreadReplyState]) {
        self.anchorPostNumber = anchorPostNumber
        self.replies = replies
    }
}

public struct TopicThreadState: Codable, Sendable {
    public var originalPostNumber: UInt32?
    public var replySections: [TopicThreadSectionState]

    public init(
        originalPostNumber: UInt32? = nil,
        replySections: [TopicThreadSectionState] = []
    ) {
        self.originalPostNumber = originalPostNumber
        self.replySections = replySections
    }
}

public struct TopicDetailCreatedByState: Codable, Sendable {
    public var id: UInt64
    public var username: String
    public var avatarTemplate: String?

    public init(id: UInt64, username: String, avatarTemplate: String?) {
        self.id = id
        self.username = username
        self.avatarTemplate = avatarTemplate
    }
}

public struct TopicDetailMetaState: Codable, Sendable {
    public var notificationLevel: Int32?
    public var canEdit: Bool
    public var createdBy: TopicDetailCreatedByState?

    public init(
        notificationLevel: Int32?,
        canEdit: Bool,
        createdBy: TopicDetailCreatedByState?
    ) {
        self.notificationLevel = notificationLevel
        self.canEdit = canEdit
        self.createdBy = createdBy
    }
}

public struct TopicDetailState: Codable, Sendable {
    public var id: UInt64
    public var title: String
    public var slug: String
    public var postsCount: UInt32
    public var categoryId: UInt64?
    public var tags: [TopicTagState]
    public var views: UInt32
    public var likeCount: UInt32
    public var createdAt: String?
    public var lastReadPostNumber: UInt32?
    public var bookmarks: [UInt64]
    public var acceptedAnswer: Bool
    public var hasAcceptedAnswer: Bool
    public var canVote: Bool
    public var voteCount: Int32
    public var userVoted: Bool
    public var summarizable: Bool
    public var hasCachedSummary: Bool
    public var hasSummary: Bool
    public var archetype: String?
    public var postStream: TopicPostStreamState
    public var thread: TopicThreadState
    public var details: TopicDetailMetaState

    public init(
        id: UInt64,
        title: String,
        slug: String,
        postsCount: UInt32,
        categoryId: UInt64?,
        tags: [TopicTagState],
        views: UInt32,
        likeCount: UInt32,
        createdAt: String?,
        lastReadPostNumber: UInt32?,
        bookmarks: [UInt64],
        acceptedAnswer: Bool,
        hasAcceptedAnswer: Bool,
        canVote: Bool,
        voteCount: Int32,
        userVoted: Bool,
        summarizable: Bool,
        hasCachedSummary: Bool,
        hasSummary: Bool,
        archetype: String?,
        postStream: TopicPostStreamState,
        thread: TopicThreadState = TopicThreadState(),
        details: TopicDetailMetaState
    ) {
        self.id = id
        self.title = title
        self.slug = slug
        self.postsCount = postsCount
        self.categoryId = categoryId
        self.tags = tags
        self.views = views
        self.likeCount = likeCount
        self.createdAt = createdAt
        self.lastReadPostNumber = lastReadPostNumber
        self.bookmarks = bookmarks
        self.acceptedAnswer = acceptedAnswer
        self.hasAcceptedAnswer = hasAcceptedAnswer
        self.canVote = canVote
        self.voteCount = voteCount
        self.userVoted = userVoted
        self.summarizable = summarizable
        self.hasCachedSummary = hasCachedSummary
        self.hasSummary = hasSummary
        self.archetype = archetype
        self.postStream = postStream
        self.thread = thread
        self.details = details
    }
}

public struct LogFileSummaryState: Codable, Sendable {
    public var relativePath: String
    public var fileName: String
    public var sizeBytes: UInt64
    public var modifiedAtUnixMs: UInt64

    public init(
        relativePath: String,
        fileName: String,
        sizeBytes: UInt64,
        modifiedAtUnixMs: UInt64
    ) {
        self.relativePath = relativePath
        self.fileName = fileName
        self.sizeBytes = sizeBytes
        self.modifiedAtUnixMs = modifiedAtUnixMs
    }
}

public struct LogFileDetailState: Codable, Sendable {
    public var relativePath: String
    public var fileName: String
    public var sizeBytes: UInt64
    public var modifiedAtUnixMs: UInt64
    public var contents: String
    public var isTruncated: Bool

    public init(
        relativePath: String,
        fileName: String,
        sizeBytes: UInt64,
        modifiedAtUnixMs: UInt64,
        contents: String,
        isTruncated: Bool
    ) {
        self.relativePath = relativePath
        self.fileName = fileName
        self.sizeBytes = sizeBytes
        self.modifiedAtUnixMs = modifiedAtUnixMs
        self.contents = contents
        self.isTruncated = isTruncated
    }
}

public enum NetworkTraceOutcomeState: String, Codable, Sendable {
    case inProgress
    case succeeded
    case failed
}

public struct NetworkTraceHeaderState: Codable, Sendable {
    public var name: String
    public var value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct NetworkTraceEventState: Codable, Sendable {
    public var sequence: UInt32
    public var timestampUnixMs: UInt64
    public var phase: String
    public var summary: String
    public var details: String?

    public init(
        sequence: UInt32,
        timestampUnixMs: UInt64,
        phase: String,
        summary: String,
        details: String?
    ) {
        self.sequence = sequence
        self.timestampUnixMs = timestampUnixMs
        self.phase = phase
        self.summary = summary
        self.details = details
    }
}

public struct NetworkTraceSummaryState: Codable, Sendable {
    public var id: UInt64
    public var callId: UInt64?
    public var operation: String
    public var method: String
    public var url: String
    public var startedAtUnixMs: UInt64
    public var finishedAtUnixMs: UInt64?
    public var durationMs: UInt64?
    public var outcome: NetworkTraceOutcomeState
    public var statusCode: UInt16?
    public var errorMessage: String?
    public var responseContentType: String?
    public var responseBodyTruncated: Bool

    public init(
        id: UInt64,
        callId: UInt64?,
        operation: String,
        method: String,
        url: String,
        startedAtUnixMs: UInt64,
        finishedAtUnixMs: UInt64?,
        durationMs: UInt64?,
        outcome: NetworkTraceOutcomeState,
        statusCode: UInt16?,
        errorMessage: String?,
        responseContentType: String?,
        responseBodyTruncated: Bool
    ) {
        self.id = id
        self.callId = callId
        self.operation = operation
        self.method = method
        self.url = url
        self.startedAtUnixMs = startedAtUnixMs
        self.finishedAtUnixMs = finishedAtUnixMs
        self.durationMs = durationMs
        self.outcome = outcome
        self.statusCode = statusCode
        self.errorMessage = errorMessage
        self.responseContentType = responseContentType
        self.responseBodyTruncated = responseBodyTruncated
    }
}

public struct NetworkTraceDetailState: Codable, Sendable {
    public var summary: NetworkTraceSummaryState
    public var requestHeaders: [NetworkTraceHeaderState]
    public var responseHeaders: [NetworkTraceHeaderState]
    public var responseBody: String?
    public var responseBodyTruncated: Bool
    public var responseBodyBytes: UInt64?
    public var events: [NetworkTraceEventState]

    public init(
        summary: NetworkTraceSummaryState,
        requestHeaders: [NetworkTraceHeaderState],
        responseHeaders: [NetworkTraceHeaderState],
        responseBody: String?,
        responseBodyTruncated: Bool,
        responseBodyBytes: UInt64?,
        events: [NetworkTraceEventState]
    ) {
        self.summary = summary
        self.requestHeaders = requestHeaders
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
        self.responseBodyTruncated = responseBodyTruncated
        self.responseBodyBytes = responseBodyBytes
        self.events = events
    }
}

public final class FireCoreHandle {
    private let storedBaseUrl: String
    private let storedWorkspacePath: String?
    private var state: SessionState

    public init(baseUrl: String?, workspacePath: String?) throws {
        let resolvedBaseUrl = baseUrl ?? "https://linux.do"
        self.storedBaseUrl = resolvedBaseUrl
        self.storedWorkspacePath = workspacePath
        self.state = SessionState.placeholder(baseUrl: resolvedBaseUrl)
    }

    public func baseUrl() throws -> String {
        storedBaseUrl
    }

    public func workspacePath() throws -> String? {
        storedWorkspacePath
    }

    public func resolveWorkspacePath(relativePath: String) throws -> String {
        guard let storedWorkspacePath, !storedWorkspacePath.isEmpty else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        let nsRelativePath = relativePath as NSString
        let normalizedComponents = nsRelativePath.pathComponents.filter { $0 != "." }
        if nsRelativePath.isAbsolutePath
            || relativePath.isEmpty
            || normalizedComponents.contains("..")
        {
            throw CocoaError(.fileReadInvalidFileName)
        }

        return URL(fileURLWithPath: storedWorkspacePath)
            .appendingPathComponent(relativePath, isDirectory: false)
            .path
    }

    public func flushLogs(sync: Bool) throws {}

    public func listLogFiles() throws -> [LogFileSummaryState] {
        []
    }

    public func readLogFile(relativePath: String) throws -> LogFileDetailState {
        LogFileDetailState(
            relativePath: relativePath,
            fileName: URL(fileURLWithPath: relativePath).lastPathComponent,
            sizeBytes: 0,
            modifiedAtUnixMs: 0,
            contents: "",
            isTruncated: false
        )
    }

    public func listNetworkTraces(limit: UInt64) throws -> [NetworkTraceSummaryState] {
        []
    }

    public func networkTraceDetail(traceId: UInt64) throws -> NetworkTraceDetailState? {
        nil
    }

    public func hasLoginSession() throws -> Bool {
        state.hasLoginSession
    }

    public func snapshot() throws -> SessionState {
        state
    }

    public func syncLoginContext(context: LoginSyncState) throws -> SessionState {
        mergeCookies(context.cookies)
        state.cookies.csrfToken = context.csrfToken ?? state.cookies.csrfToken
        state.bootstrap.currentUsername = context.username ?? state.bootstrap.currentUsername
        if let homeHtml = context.homeHtml, !homeHtml.isEmpty {
            state.bootstrap.preloadedJson = homeHtml
            state.bootstrap.hasPreloadedData = true
        }
        updateDerivedState()
        return state
    }

    public func mergePlatformCookies(cookies: [PlatformCookieState]) throws -> SessionState {
        mergeCookies(cookies)
        updateDerivedState()
        return state
    }

    public func refreshBootstrap() throws -> SessionState {
        state.bootstrap.hasPreloadedData = true
        if state.bootstrap.currentUsername == nil {
            state.bootstrap.currentUsername = "guest"
        }
        updateDerivedState()
        return state
    }

    public func refreshBootstrapIfNeeded() throws -> SessionState {
        let needsBootstrapRefresh = !state.bootstrap.hasPreloadedData
            || !state.readiness.hasCurrentUser
            || !state.readiness.hasSharedSessionKey
        if state.readiness.canReadAuthenticatedApi && needsBootstrapRefresh {
            return try refreshBootstrap()
        }
        return state
    }

    public func refreshCsrfToken() throws -> SessionState {
        if state.cookies.csrfToken == nil {
            state.cookies.csrfToken = UUID().uuidString
        }
        updateDerivedState()
        return state
    }

    public func refreshCsrfTokenIfNeeded() throws -> SessionState {
        if state.cookies.csrfToken != nil {
            return state
        }
        return try refreshCsrfToken()
    }

    public func exportSessionJson() throws -> String {
        let data = try JSONEncoder().encode(state)
        return String(decoding: data, as: UTF8.self)
    }

    public func restoreSessionJson(json: String) throws -> SessionState {
        let data = Data(json.utf8)
        state = try JSONDecoder().decode(SessionState.self, from: data)
        updateDerivedState()
        return state
    }

    public func saveSessionToPath(path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try exportSessionJson().write(to: url, atomically: true, encoding: .utf8)
    }

    public func loadSessionFromPath(path: String) throws -> SessionState {
        let url = URL(fileURLWithPath: path)
        let payload = try String(contentsOf: url, encoding: .utf8)
        return try restoreSessionJson(json: payload)
    }

    public func fetchTopicList(query: TopicListQueryState) throws -> TopicListState {
        if (query.kind == .unread || query.kind == .unseen) && !state.readiness.canReadAuthenticatedApi {
            throw NSError(
                domain: "FireBindingsStub",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Authenticated topic list requires a login session."]
            )
        }

        let allTopics = sampleTopics(for: query.kind)
        let topics = query.topicIds.isEmpty
            ? allTopics
            : allTopics.filter { query.topicIds.contains($0.id) }

        return TopicListState(
            topics: topics,
            users: sampleUsers(),
            rows: sampleTopicRows(topics: topics, users: sampleUsers()),
            moreTopicsUrl: "/latest?page=1",
            nextPage: 1
        )
    }

    public func fetchTopicDetail(query: TopicDetailQueryState) throws -> TopicDetailState {
        guard let detail = sampleTopicDetail(topicId: query.topicId) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return detail
    }

    public func createReply(request: TopicReplyRequestState) throws -> TopicPostState {
        let username = state.bootstrap.currentUsername ?? "guest"
        let postNumber = (request.replyToPostNumber ?? 1) + 1
        let timestamp = ISO8601DateFormatter().string(from: Date())
        return TopicPostState(
            id: UInt64.random(in: 10_000...99_999),
            username: username,
            name: username.capitalized,
            avatarTemplate: "/user_avatar/linux.do/\(username)/{size}/3.png",
            cooked: "<p>\(request.raw)</p>",
            postNumber: postNumber,
            postType: 1,
            createdAt: timestamp,
            updatedAt: timestamp,
            likeCount: 0,
            replyCount: 0,
            replyToPostNumber: request.replyToPostNumber,
            bookmarked: false,
            bookmarkId: nil,
            reactions: [],
            currentUserReaction: nil,
            acceptedAnswer: false,
            canEdit: true,
            canDelete: true,
            canRecover: false,
            hidden: false
        )
    }

    public func likePost(postId: UInt64) throws {}

    public func unlikePost(postId: UInt64) throws {}

    public func togglePostReaction(
        postId: UInt64,
        reactionId: String
    ) throws -> PostReactionUpdateState {
        PostReactionUpdateState(
            reactions: [TopicReactionState(id: reactionId, kind: "emoji", count: 1)],
            currentUserReaction: TopicReactionState(id: reactionId, kind: "emoji", count: 1)
        )
    }

    public func clearSessionPath(path: String) throws {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func logoutRemote(preserveCfClearance: Bool) throws -> SessionState {
        let clearance = preserveCfClearance ? state.cookies.cfClearance : nil
        state = SessionState.placeholder(baseUrl: storedBaseUrl)
        state.cookies.cfClearance = clearance
        updateDerivedState()
        return state
    }

    private func mergeCookies(_ cookies: [PlatformCookieState]) {
        for cookie in cookies {
            switch cookie.name {
            case "_t":
                state.cookies.tToken = cookie.value
            case "_forum_session":
                state.cookies.forumSession = cookie.value
            case "cf_clearance":
                state.cookies.cfClearance = cookie.value
            default:
                continue
            }
        }
    }

    private func updateDerivedState() {
        let hasLoginCookie = !(state.cookies.tToken?.isEmpty ?? true)
        let hasForumSession = !(state.cookies.forumSession?.isEmpty ?? true)
        let hasCsrfToken = !(state.cookies.csrfToken?.isEmpty ?? true)
        let hasCurrentUser = !(state.bootstrap.currentUsername?.isEmpty ?? true)
        let hasSharedSessionKey = !(state.bootstrap.sharedSessionKey?.isEmpty ?? true)
        let canReadAuthenticatedApi = hasLoginCookie && hasForumSession
        let canWriteAuthenticatedApi = canReadAuthenticatedApi && hasCsrfToken
        let canOpenMessageBus = canReadAuthenticatedApi && hasSharedSessionKey

        state.readiness = SessionReadinessState(
            hasLoginCookie: hasLoginCookie,
            hasForumSession: hasForumSession,
            hasCloudflareClearance: !(state.cookies.cfClearance?.isEmpty ?? true),
            hasCsrfToken: hasCsrfToken,
            hasCurrentUser: hasCurrentUser,
            hasPreloadedData: state.bootstrap.hasPreloadedData,
            hasSharedSessionKey: hasSharedSessionKey,
            canReadAuthenticatedApi: canReadAuthenticatedApi,
            canWriteAuthenticatedApi: canWriteAuthenticatedApi,
            canOpenMessageBus: canOpenMessageBus
        )
        state.hasLoginSession = hasLoginCookie
        state.loginPhase = {
            if !hasLoginCookie { return .anonymous }
            if !canReadAuthenticatedApi || !hasCurrentUser { return .cookiesCaptured }
            if !canWriteAuthenticatedApi || !state.bootstrap.hasPreloadedData { return .bootstrapCaptured }
            return .ready
        }()
        state.profileDisplayName = {
            if let username = state.bootstrap.currentUsername, !username.isEmpty {
                return username
            }
            if canReadAuthenticatedApi || hasLoginCookie {
                return "会话已连接"
            }
            return "未登录"
        }()
        state.loginPhaseLabel = {
            if canReadAuthenticatedApi && !hasCurrentUser {
                return "账号信息同步中"
            }
            switch state.loginPhase {
            case .anonymous:
                return "未登录"
            case .cookiesCaptured:
                return "Cookie 已同步"
            case .bootstrapCaptured:
                return "会话初始化中"
            case .ready:
                return "已就绪"
            }
        }()
    }

    private func sampleUsers() -> [TopicUserState] {
        let currentUsername = state.bootstrap.currentUsername ?? "guest"
        return [
            TopicUserState(id: 1, username: "alice", avatarTemplate: "/user_avatar/linux.do/alice/{size}/1.png"),
            TopicUserState(id: 2, username: "bob", avatarTemplate: "/user_avatar/linux.do/bob/{size}/2.png"),
            TopicUserState(id: 3, username: currentUsername, avatarTemplate: "/user_avatar/linux.do/\(currentUsername)/{size}/3.png"),
        ]
    }

    private func sampleTopicRows(
        topics: [TopicSummaryState],
        users: [TopicUserState]
    ) -> [TopicRowState] {
        let usersById = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
        return topics.map { topic in
            let originalPoster = topic.posters.first.flatMap { usersById[$0.userId] }
            return TopicRowState(
                topic: topic,
                excerptText: topic.excerpt,
                originalPosterUsername: originalPoster?.username,
                originalPosterAvatarTemplate: originalPoster?.avatarTemplate,
                tagNames: topic.tags.compactMap { !$0.name.isEmpty ? $0.name : $0.slug },
                createdTimestampUnixMs: nil,
                activityTimestampUnixMs: nil,
                lastPosterUsername: topic.lastPosterUsername
            )
        }
    }

    private func sampleTopics(for kind: TopicListKindState) -> [TopicSummaryState] {
        let topics = [
            TopicSummaryState(
                id: 123,
                title: "Fire native shell now reaches the first read path",
                slug: "fire-native-first-read-path",
                postsCount: 24,
                replyCount: 18,
                views: 512,
                likeCount: 34,
                excerpt: "Login, bootstrap, and the first authenticated topic flow are now connected in the host shells.",
                createdAt: "2026-03-28T09:30:00Z",
                lastPostedAt: "2026-03-28T11:10:00Z",
                lastPosterUsername: "alice",
                categoryId: 2,
                pinned: false,
                visible: true,
                closed: false,
                archived: false,
                tags: [
                    TopicTagState(id: nil, name: "fire", slug: nil),
                    TopicTagState(id: nil, name: "native", slug: nil),
                ],
                posters: [
                    TopicPosterState(userId: 1, description: "Original Poster", extras: nil),
                    TopicPosterState(userId: 3, description: "Frequent Poster", extras: "latest"),
                ],
                unseen: false,
                unreadPosts: 3,
                newPosts: 1,
                lastReadPostNumber: 21,
                highestPostNumber: 24,
                hasAcceptedAnswer: false,
                canHaveAnswer: true
            ),
            TopicSummaryState(
                id: 124,
                title: "Next up: replace host stubs with generated UniFFI bindings",
                slug: "replace-host-stubs-with-uniffi",
                postsCount: 13,
                replyCount: 8,
                views: 340,
                likeCount: 22,
                excerpt: "The shell UI is in place, but the temporary Swift/Kotlin shims still need to be swapped for generated bindings.",
                createdAt: "2026-03-28T08:45:00Z",
                lastPostedAt: "2026-03-28T10:50:00Z",
                lastPosterUsername: state.bootstrap.currentUsername ?? "guest",
                categoryId: 3,
                pinned: false,
                visible: true,
                closed: false,
                archived: false,
                tags: [
                    TopicTagState(id: nil, name: "uniffi", slug: nil),
                    TopicTagState(id: nil, name: "roadmap", slug: nil),
                ],
                posters: [
                    TopicPosterState(userId: 2, description: "Original Poster", extras: nil),
                    TopicPosterState(userId: 3, description: "Most Recent Poster", extras: nil),
                ],
                unseen: true,
                unreadPosts: 5,
                newPosts: 2,
                lastReadPostNumber: 8,
                highestPostNumber: 13,
                hasAcceptedAnswer: true,
                canHaveAnswer: true
            ),
            TopicSummaryState(
                id: 125,
                title: "MessageBus orchestration planning thread",
                slug: "messagebus-orchestration-planning-thread",
                postsCount: 9,
                replyCount: 4,
                views: 201,
                likeCount: 11,
                excerpt: "Shared session key and topic tracking metadata are ready to feed the next real-time step.",
                createdAt: "2026-03-27T16:15:00Z",
                lastPostedAt: "2026-03-28T07:20:00Z",
                lastPosterUsername: "bob",
                categoryId: 4,
                pinned: false,
                visible: true,
                closed: false,
                archived: false,
                tags: [
                    TopicTagState(id: nil, name: "messagebus", slug: nil),
                ],
                posters: [
                    TopicPosterState(userId: 2, description: "Original Poster", extras: nil),
                ],
                unseen: false,
                unreadPosts: 0,
                newPosts: 0,
                lastReadPostNumber: 9,
                highestPostNumber: 9,
                hasAcceptedAnswer: false,
                canHaveAnswer: false
            ),
        ]

        switch kind {
        case .latest:
            return topics
        case .new:
            return Array(topics.prefix(2))
        case .unread, .unseen:
            return topics.filter { $0.unreadPosts > 0 || $0.unseen }
        case .hot:
            return [topics[1], topics[0]]
        case .top:
            return topics.sorted { $0.likeCount > $1.likeCount }
        }
    }

    private func sampleTopicDetail(topicId: UInt64) -> TopicDetailState? {
        let currentUsername = state.bootstrap.currentUsername ?? "guest"

        switch topicId {
        case 123:
            return TopicDetailState(
                id: 123,
                title: "Fire native shell now reaches the first read path",
                slug: "fire-native-first-read-path",
                postsCount: 24,
                categoryId: 2,
                tags: [
                    TopicTagState(id: nil, name: "fire", slug: nil),
                    TopicTagState(id: nil, name: "native", slug: nil),
                ],
                views: 512,
                likeCount: 34,
                createdAt: "2026-03-28T09:30:00Z",
                lastReadPostNumber: 21,
                bookmarks: [],
                acceptedAnswer: false,
                hasAcceptedAnswer: false,
                canVote: false,
                voteCount: 0,
                userVoted: false,
                summarizable: true,
                hasCachedSummary: false,
                hasSummary: false,
                archetype: "regular",
                postStream: TopicPostStreamState(
                    posts: [
                        TopicPostState(
                            id: 9001,
                            username: "alice",
                            name: "Alice",
                            avatarTemplate: "/user_avatar/linux.do/alice/{size}/1.png",
                            cooked: "<p>登录流程已经可用了，接下来先把第一个已登录读取链路打通。</p>",
                            postNumber: 1,
                            postType: 1,
                            createdAt: "2026-03-28T09:30:00Z",
                            updatedAt: "2026-03-28T09:35:00Z",
                            likeCount: 12,
                            replyCount: 1,
                            replyToPostNumber: nil,
                            bookmarked: false,
                            bookmarkId: nil,
                            reactions: [TopicReactionState(id: "heart", kind: "like", count: 12)],
                            currentUserReaction: nil,
                            acceptedAnswer: false,
                            canEdit: false,
                            canDelete: false,
                            canRecover: false,
                            hidden: false
                        ),
                        TopicPostState(
                            id: 9002,
                            username: currentUsername,
                            name: currentUsername.capitalized,
                            avatarTemplate: "/user_avatar/linux.do/\(currentUsername)/{size}/3.png",
                            cooked: "<p>现在 host shell 可以直接加载 latest 列表，并打开 topic detail 预览帖子内容。</p>",
                            postNumber: 2,
                            postType: 1,
                            createdAt: "2026-03-28T10:05:00Z",
                            updatedAt: "2026-03-28T10:05:00Z",
                            likeCount: 4,
                            replyCount: 0,
                            replyToPostNumber: 1,
                            bookmarked: false,
                            bookmarkId: nil,
                            reactions: [],
                            currentUserReaction: nil,
                            acceptedAnswer: false,
                            canEdit: true,
                            canDelete: false,
                            canRecover: false,
                            hidden: false
                        ),
                    ],
                    stream: [9001, 9002]
                ),
                details: TopicDetailMetaState(
                    notificationLevel: 1,
                    canEdit: false,
                    createdBy: TopicDetailCreatedByState(
                        id: 1,
                        username: "alice",
                        avatarTemplate: "/user_avatar/linux.do/alice/{size}/1.png"
                    )
                )
            )
        case 124:
            return TopicDetailState(
                id: 124,
                title: "Next up: replace host stubs with generated UniFFI bindings",
                slug: "replace-host-stubs-with-uniffi",
                postsCount: 13,
                categoryId: 3,
                tags: [
                    TopicTagState(id: nil, name: "uniffi", slug: nil),
                    TopicTagState(id: nil, name: "roadmap", slug: nil),
                ],
                views: 340,
                likeCount: 22,
                createdAt: "2026-03-28T08:45:00Z",
                lastReadPostNumber: 8,
                bookmarks: [1240],
                acceptedAnswer: true,
                hasAcceptedAnswer: true,
                canVote: false,
                voteCount: 0,
                userVoted: false,
                summarizable: true,
                hasCachedSummary: false,
                hasSummary: false,
                archetype: "regular",
                postStream: TopicPostStreamState(
                    posts: [
                        TopicPostState(
                            id: 9101,
                            username: "bob",
                            name: "Bob",
                            avatarTemplate: "/user_avatar/linux.do/bob/{size}/2.png",
                            cooked: "<p>当前 topic UI 先走临时 shim，下一步要把它替换成真正生成的 UniFFI bindings。</p>",
                            postNumber: 1,
                            postType: 1,
                            createdAt: "2026-03-28T08:45:00Z",
                            updatedAt: "2026-03-28T08:50:00Z",
                            likeCount: 9,
                            replyCount: 0,
                            replyToPostNumber: nil,
                            bookmarked: true,
                            bookmarkId: 1240,
                            reactions: [TopicReactionState(id: "heart", kind: "like", count: 9)],
                            currentUserReaction: nil,
                            acceptedAnswer: true,
                            canEdit: false,
                            canDelete: false,
                            canRecover: false,
                            hidden: false
                        ),
                    ],
                    stream: [9101]
                ),
                details: TopicDetailMetaState(
                    notificationLevel: 2,
                    canEdit: false,
                    createdBy: TopicDetailCreatedByState(
                        id: 2,
                        username: "bob",
                        avatarTemplate: "/user_avatar/linux.do/bob/{size}/2.png"
                    )
                )
            )
        case 125:
            return TopicDetailState(
                id: 125,
                title: "MessageBus orchestration planning thread",
                slug: "messagebus-orchestration-planning-thread",
                postsCount: 9,
                categoryId: 4,
                tags: [
                    TopicTagState(id: nil, name: "messagebus", slug: nil),
                ],
                views: 201,
                likeCount: 11,
                createdAt: "2026-03-27T16:15:00Z",
                lastReadPostNumber: 9,
                bookmarks: [],
                acceptedAnswer: false,
                hasAcceptedAnswer: false,
                canVote: false,
                voteCount: 0,
                userVoted: false,
                summarizable: true,
                hasCachedSummary: false,
                hasSummary: false,
                archetype: "regular",
                postStream: TopicPostStreamState(
                    posts: [
                        TopicPostState(
                            id: 9201,
                            username: "bob",
                            name: "Bob",
                            avatarTemplate: "/user_avatar/linux.do/bob/{size}/2.png",
                            cooked: "<p>shared_session_key 和 topicTrackingStateMeta 已经在 bootstrap 里了，下一步是把 MessageBus 长轮询拉起来。</p>",
                            postNumber: 1,
                            postType: 1,
                            createdAt: "2026-03-27T16:15:00Z",
                            updatedAt: "2026-03-27T16:15:00Z",
                            likeCount: 6,
                            replyCount: 0,
                            replyToPostNumber: nil,
                            bookmarked: false,
                            bookmarkId: nil,
                            reactions: [],
                            currentUserReaction: nil,
                            acceptedAnswer: false,
                            canEdit: false,
                            canDelete: false,
                            canRecover: false,
                            hidden: false
                        ),
                    ],
                    stream: [9201]
                ),
                details: TopicDetailMetaState(
                    notificationLevel: 1,
                    canEdit: false,
                    createdBy: TopicDetailCreatedByState(
                        id: 2,
                        username: "bob",
                        avatarTemplate: "/user_avatar/linux.do/bob/{size}/2.png"
                    )
                )
            )
        default:
            return nil
        }
    }
}
#endif
