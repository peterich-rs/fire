package com.fire.app.session

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import org.json.JSONObject
import uniffi.fire_uniffi.FireAppCore
import uniffi.fire_uniffi_diagnostics.LogFileDetailState
import uniffi.fire_uniffi_diagnostics.LogFileSummaryState
import uniffi.fire_uniffi_diagnostics.NetworkTraceDetailState
import uniffi.fire_uniffi_diagnostics.NetworkTraceSummaryState
import uniffi.fire_uniffi_diagnostics.HostLogLevelState
import uniffi.fire_uniffi_messagebus.MessageBusClientModeState
import uniffi.fire_uniffi_messagebus.MessageBusEventHandler
import uniffi.fire_uniffi_messagebus.MessageBusSubscriptionScopeState
import uniffi.fire_uniffi_messagebus.MessageBusSubscriptionState
import uniffi.fire_uniffi_messagebus.TopicPresenceState
import uniffi.fire_uniffi_notifications.NotificationCenterState
import uniffi.fire_uniffi_notifications.NotificationListState
import uniffi.fire_uniffi_search.SearchQueryState
import uniffi.fire_uniffi_search.SearchResultState
import uniffi.fire_uniffi_search.TagSearchQueryState
import uniffi.fire_uniffi_search.TagSearchResultState
import uniffi.fire_uniffi_search.UserMentionQueryState
import uniffi.fire_uniffi_search.UserMentionResultState
import uniffi.fire_uniffi_session.AppStateRefreshHandler
import uniffi.fire_uniffi_session.CookieReplayEntryState
import uniffi.fire_uniffi_session.CurrentUserSnapshotState
import uniffi.fire_uniffi_session.HomeTopicListScopeState
import uniffi.fire_uniffi_session.LoginFinalizationResultState
import uniffi.fire_uniffi_session.LoginStateDeterminationState
import uniffi.fire_uniffi_session.LoginSyncState
import uniffi.fire_uniffi_session.PlatformCookieState
import uniffi.fire_uniffi_session.RefreshTriggerState
import uniffi.fire_uniffi_session.SessionState
import uniffi.fire_uniffi_types.DraftDataState
import uniffi.fire_uniffi_types.DraftState
import uniffi.fire_uniffi_topics.PollState
import uniffi.fire_uniffi_topics.PostActionTypeState
import uniffi.fire_uniffi_topics.PostFlagRequestState
import uniffi.fire_uniffi_topics.PostReactionUpdateState
import uniffi.fire_uniffi_topics.PostUpdateRequestState
import uniffi.fire_uniffi_topics.PrivateMessageCreateRequestState
import uniffi.fire_uniffi_topics.ReactionUsersGroupState
import uniffi.fire_uniffi_topics.ResolvedUploadUrlState
import uniffi.fire_uniffi_topics.TopicAiSummaryState
import uniffi.fire_uniffi_topics.TopicCreateRequestState
import uniffi.fire_uniffi_topics.TopicDetailQueryState
import uniffi.fire_uniffi_topics.TopicDetailState
import uniffi.fire_uniffi_topics.TopicListQueryState
import uniffi.fire_uniffi_topics.TopicPostState
import uniffi.fire_uniffi_topics.TopicResponsePageQueryState
import uniffi.fire_uniffi_topics.TopicResponsePageState
import uniffi.fire_uniffi_topics.TopicReplyRequestState
import uniffi.fire_uniffi_topics.TopicScreenQueryState
import uniffi.fire_uniffi_topics.TopicScreenState
import uniffi.fire_uniffi_topics.TopicUpdateRequestState
import uniffi.fire_uniffi_topics.UploadImageRequestState
import uniffi.fire_uniffi_topics.UploadResultState
import uniffi.fire_uniffi_topics.VoteResponseState
import uniffi.fire_uniffi_topics.VotedUserState
import uniffi.fire_uniffi_types.TopicListState
import uniffi.fire_uniffi_user.FollowUserState
import uniffi.fire_uniffi_user.UserProfileState
import uniffi.fire_uniffi_user.UserReactionsState
import uniffi.fire_uniffi_user.UserSummaryState

class FireSessionStore(
    context: Context,
    baseUrl: String? = null,
    workspacePath: String? = null,
    sessionFilePath: String? = null,
) {
    private val workspaceDir: File
    private val core: FireAppCore
    private val sessionFile: File

    init {
        val resolvedWorkspacePath = workspacePath
            ?: sessionFilePath?.let { File(it).parentFile?.absolutePath }
            ?: defaultWorkspacePath(context)
        workspaceDir = File(resolvedWorkspacePath)
        core = FireAppCore(baseUrl, workspaceDir.absolutePath)
        sessionFile = File(sessionFilePath ?: core.session().resolveWorkspacePath("session.json"))
    }

    suspend fun snapshot(): SessionState = withContext(Dispatchers.Default) {
        core.session().snapshot()
    }

    suspend fun restorePersistedSessionIfAvailable(): SessionState? = withContext(Dispatchers.IO) {
        if (!sessionFile.exists()) {
            return@withContext null
        }
        core.session().loadSessionFromPath(sessionFile.absolutePath)
    }

    suspend fun prepareStartupSession(): SessionState = withContext(Dispatchers.IO) {
        restorePersistedSessionIfAvailable() ?: core.session().snapshot()
    }

    suspend fun baseUrl(): String = withContext(Dispatchers.Default) {
        core.session().baseUrl()
    }

    suspend fun syncLoginContext(captured: FireCapturedLoginState): SessionState =
        withContext(Dispatchers.Default) {
            val state = core.session().syncLoginContext(
                LoginSyncState(
                    currentUrl = captured.currentUrl,
                    username = captured.username,
                    csrfToken = captured.csrfToken,
                    homeHtml = captured.homeHtml,
                    browserUserAgent = captured.browserUserAgent,
                    cookies = captured.cookies,
                ),
            )
            persistCurrentSession()
            state
        }

    suspend fun cookieReplayQueue(): List<CookieReplayEntryState> = withContext(Dispatchers.IO) {
        core.session().cookieReplayQueue()
    }

    suspend fun clearCookieReplayQueue() = withContext(Dispatchers.IO) {
        core.session().clearCookieReplayQueue()
    }

    suspend fun finalizeLoginFromWebView(
        captured: FireCapturedLoginState,
        allowLowConfidenceSessionCookies: Boolean = true,
    ): LoginFinalizationResultState = withContext(Dispatchers.Default) {
        val result = core.session().finalizeLoginFromWebview(
            username = captured.username.orEmpty(),
            csrfToken = captured.csrfToken,
            rawPreloadedHtml = captured.homeHtml,
            browserUserAgent = captured.browserUserAgent,
            cookies = captured.cookies,
            allowLowConfidenceSessionCookies = allowLowConfidenceSessionCookies,
        )
        persistCurrentSession()
        result
    }

    suspend fun applyPlatformCookies(cookies: List<PlatformCookieState>): SessionState =
        withContext(Dispatchers.Default) {
            val state = core.session().applyPlatformCookies(cookies)
            persistCurrentSession()
            state
        }

    suspend fun refreshBootstrapIfNeeded(): SessionState = withContext(Dispatchers.IO) {
        val refreshed = core.session().refreshBootstrapIfNeeded()
        persistCurrentSession()
        refreshed
    }

    suspend fun refreshBootstrap(): SessionState = withContext(Dispatchers.IO) {
        val refreshed = core.session().refreshBootstrap()
        persistCurrentSession()
        refreshed
    }

    suspend fun refreshCsrfTokenIfNeeded(): SessionState = withContext(Dispatchers.IO) {
        val refreshed = core.session().refreshCsrfTokenIfNeeded()
        persistCurrentSession()
        refreshed
    }

    suspend fun logoutLocal(preserveCfClearance: Boolean = true): SessionState =
        withContext(Dispatchers.IO) {
            val state = core.session().logoutLocal(preserveCfClearance)
            persistCurrentSession()
            state
        }

    suspend fun recordFingerprintDone() = withContext(Dispatchers.Default) {
        core.session().recordFingerprintDone()
    }

    suspend fun persistCurrentSession() = withContext(Dispatchers.IO) {
        sessionFile.parentFile?.mkdirs()
        core.session().saveSessionToPath(sessionFile.absolutePath)
    }

    fun workspacePath(): String = workspaceDir.absolutePath

    fun diagnosticSessionId(): String = core.diagnostics().diagnosticSessionId()

    fun logHost(level: HostLogLevelState, target: String, message: String) {
        core.diagnostics().logHost(level, target, message)
    }

    fun flushLogs(sync: Boolean) {
        core.diagnostics().flushLogs(sync)
    }

    suspend fun listLogFiles(): List<LogFileSummaryState> =
        withContext(Dispatchers.IO) {
            core.diagnostics().listLogFiles()
        }

    suspend fun readLogFile(relativePath: String): LogFileDetailState =
        withContext(Dispatchers.IO) {
            core.diagnostics().readLogFile(relativePath)
        }

    suspend fun listNetworkTraces(limit: ULong = 200uL): List<NetworkTraceSummaryState> =
        withContext(Dispatchers.IO) {
            core.diagnostics().listNetworkTraces(limit)
        }

    suspend fun networkTraceDetail(traceId: ULong): NetworkTraceDetailState? =
        withContext(Dispatchers.IO) {
            core.diagnostics().networkTraceDetail(traceId)
        }

    suspend fun exportSessionJson(): String = withContext(Dispatchers.Default) {
        core.session().exportSessionJson()
    }

    suspend fun notificationState(): NotificationCenterState = withContext(Dispatchers.Default) {
        core.notifications().notificationState()
    }

    suspend fun fetchRecentNotifications(limit: UInt? = null): NotificationListState =
        withContext(Dispatchers.IO) {
            core.notifications().fetchRecentNotifications(limit)
        }

    suspend fun fetchNotifications(
        limit: UInt? = null,
        offset: UInt? = null,
    ): NotificationListState = withContext(Dispatchers.IO) {
        core.notifications().fetchNotifications(limit, offset)
    }

    suspend fun fetchBookmarks(username: String, page: UInt? = null): TopicListState =
        withContext(Dispatchers.IO) {
            core.notifications().fetchBookmarks(username, page)
        }

    suspend fun fetchReadHistory(page: UInt? = null): TopicListState =
        withContext(Dispatchers.IO) {
            core.notifications().fetchReadHistory(page)
        }

    suspend fun fetchDraft(draftKey: String): DraftState? = withContext(Dispatchers.IO) {
        core.notifications().fetchDraft(draftKey)
    }

    suspend fun saveDraft(
        draftKey: String,
        data: DraftDataState,
        sequence: UInt,
    ): UInt = withContext(Dispatchers.IO) {
        core.notifications().saveDraft(draftKey, data, sequence)
    }

    suspend fun deleteDraft(draftKey: String, sequence: UInt?) = withContext(Dispatchers.IO) {
        core.notifications().deleteDraft(draftKey, sequence)
    }

    suspend fun createBookmark(
        bookmarkableId: ULong,
        bookmarkableType: String,
        name: String? = null,
        reminderAt: String? = null,
        autoDeletePreference: Int? = null,
    ): ULong = withContext(Dispatchers.IO) {
        val bookmarkId = core.notifications().createBookmark(
            bookmarkableId,
            bookmarkableType,
            name,
            reminderAt,
            autoDeletePreference,
        )
        persistCurrentSession()
        bookmarkId
    }

    suspend fun updateBookmark(
        bookmarkId: ULong,
        name: String? = null,
        reminderAt: String? = null,
        autoDeletePreference: Int? = null,
    ) = withContext(Dispatchers.IO) {
        core.notifications().updateBookmark(
            bookmarkId,
            name,
            reminderAt,
            autoDeletePreference,
        )
        persistCurrentSession()
    }

    suspend fun deleteBookmark(bookmarkId: ULong) = withContext(Dispatchers.IO) {
        core.notifications().deleteBookmark(bookmarkId)
        persistCurrentSession()
    }

    suspend fun setTopicNotificationLevel(topicId: ULong, notificationLevel: Int) =
        withContext(Dispatchers.IO) {
            core.notifications().setTopicNotificationLevel(topicId, notificationLevel)
            persistCurrentSession()
        }

    suspend fun setCategoryNotificationLevel(categoryId: ULong, notificationLevel: Int) =
        withContext(Dispatchers.IO) {
            core.notifications().setCategoryNotificationLevel(categoryId, notificationLevel)
            persistCurrentSession()
        }

    suspend fun markNotificationRead(id: ULong): NotificationCenterState =
        withContext(Dispatchers.IO) {
            core.notifications().markNotificationRead(id)
        }

    suspend fun markAllNotificationsRead(): NotificationCenterState =
        withContext(Dispatchers.IO) {
            core.notifications().markAllNotificationsRead()
        }

    suspend fun search(query: SearchQueryState): SearchResultState = withContext(Dispatchers.IO) {
        core.search().search(query)
    }

    suspend fun searchTags(query: TagSearchQueryState): TagSearchResultState = withContext(Dispatchers.IO) {
        core.search().searchTags(query)
    }

    suspend fun searchUsers(query: UserMentionQueryState): UserMentionResultState = withContext(Dispatchers.IO) {
        core.search().searchUsers(query)
    }

    suspend fun restoreSessionJson(json: String): SessionState = withContext(Dispatchers.Default) {
        val restored = core.session().restoreSessionJson(json)
        persistCurrentSession()
        restored
    }

    suspend fun logout(): SessionState = withContext(Dispatchers.IO) {
        val state = runCatching { core.session().logoutRemote(true) }
            .getOrElse { core.session().logoutLocal(true) }
        clearPersistedSession()
        state
    }

    suspend fun fetchTopicList(query: TopicListQueryState): TopicListState = withContext(Dispatchers.IO) {
        val response = core.topics().fetchTopicList(query)
        persistCurrentSession()
        response
    }

    suspend fun fetchTopicDetail(query: TopicDetailQueryState): TopicDetailState = withContext(Dispatchers.IO) {
        core.topics().fetchTopicDetail(query)
    }

    suspend fun fetchTopicDetailInitial(query: TopicDetailQueryState): TopicDetailState = withContext(Dispatchers.IO) {
        core.topics().fetchTopicDetailInitial(query)
    }

    suspend fun fetchTopicScreen(query: TopicScreenQueryState): TopicScreenState = withContext(Dispatchers.IO) {
        core.topics().fetchTopicScreen(query)
    }

    suspend fun fetchTopicResponsePage(query: TopicResponsePageQueryState): TopicResponsePageState = withContext(Dispatchers.IO) {
        core.topics().fetchTopicResponsePage(query)
    }

    suspend fun startMessageBus(handler: MessageBusEventHandler): String = withContext(Dispatchers.IO) {
        val clientId = core.messagebus().startMessageBus(
            MessageBusClientModeState.FOREGROUND,
            handler,
            topicTrackingStateMetaForMessageBus(),
        )
        persistCurrentSession()
        clientId
    }

    fun stopMessageBus(clearSubscriptions: Boolean = false) {
        core.messagebus().stopMessageBus(clearSubscriptions)
    }

    fun subscribeTopicDetailChannel(topicId: ULong, ownerToken: String, lastMessageId: Long?) {
        core.messagebus().subscribeChannel(
            MessageBusSubscriptionState(
                ownerToken = ownerToken,
                channel = "/topic/$topicId",
                lastMessageId = lastMessageId,
                scope = MessageBusSubscriptionScopeState.TRANSIENT,
            ),
        )
    }

    fun unsubscribeTopicDetailChannel(topicId: ULong, ownerToken: String) {
        core.messagebus().unsubscribeChannel(ownerToken = ownerToken, channel = "/topic/$topicId")
    }

    fun subscribeTopicReactionChannel(topicId: ULong, ownerToken: String) {
        core.messagebus().subscribeChannel(
            MessageBusSubscriptionState(
                ownerToken = ownerToken,
                channel = "/topic/$topicId/reactions",
                lastMessageId = null,
                scope = MessageBusSubscriptionScopeState.TRANSIENT,
            ),
        )
    }

    fun unsubscribeTopicReactionChannel(topicId: ULong, ownerToken: String) {
        core.messagebus().unsubscribeChannel(ownerToken = ownerToken, channel = "/topic/$topicId/reactions")
    }

    fun subscribeTopicPollsChannel(topicId: ULong, ownerToken: String) {
        core.messagebus().subscribeChannel(
            MessageBusSubscriptionState(
                ownerToken = ownerToken,
                channel = "/polls/$topicId",
                lastMessageId = 0,
                scope = MessageBusSubscriptionScopeState.TRANSIENT,
            ),
        )
    }

    fun unsubscribeTopicPollsChannel(topicId: ULong, ownerToken: String) {
        core.messagebus().unsubscribeChannel(ownerToken = ownerToken, channel = "/polls/$topicId")
    }

    suspend fun bootstrapTopicReplyPresence(topicId: ULong, ownerToken: String): TopicPresenceState =
        withContext(Dispatchers.IO) {
            core.messagebus().bootstrapTopicReplyPresence(topicId, ownerToken)
        }

    fun unsubscribeTopicReplyPresenceChannel(topicId: ULong, ownerToken: String) {
        core.messagebus().unsubscribeChannel(
            ownerToken = ownerToken,
            channel = "/presence/discourse-presence/reply/$topicId",
        )
    }

    suspend fun fetchTopicPosts(topicId: ULong, postIds: List<ULong>): List<TopicPostState> = withContext(Dispatchers.IO) {
        core.topics().fetchTopicPosts(topicId, postIds)
    }

    suspend fun fetchPost(postId: ULong): TopicPostState = withContext(Dispatchers.IO) {
        core.topics().fetchPost(postId)
    }

    suspend fun fetchTopicAiSummary(topicId: ULong, skipAgeCheck: Boolean = false): TopicAiSummaryState? =
        withContext(Dispatchers.IO) {
            core.topics().fetchTopicAiSummary(topicId, skipAgeCheck)
        }

    suspend fun createTopic(input: TopicCreateRequestState): ULong = withContext(Dispatchers.IO) {
        val topicId = core.topics().createTopic(input)
        persistCurrentSession()
        topicId
    }

    suspend fun createPrivateMessage(input: PrivateMessageCreateRequestState): ULong = withContext(Dispatchers.IO) {
        val topicId = core.topics().createPrivateMessage(input)
        persistCurrentSession()
        topicId
    }

    suspend fun createReply(input: TopicReplyRequestState): TopicPostState = withContext(Dispatchers.IO) {
        val post = core.topics().createReply(input)
        persistCurrentSession()
        post
    }

    suspend fun updateTopic(input: TopicUpdateRequestState) = withContext(Dispatchers.IO) {
        core.topics().updateTopic(input)
        persistCurrentSession()
    }

    suspend fun updatePost(input: PostUpdateRequestState): TopicPostState = withContext(Dispatchers.IO) {
        val post = core.topics().updatePost(input)
        persistCurrentSession()
        post
    }

    suspend fun uploadImage(input: UploadImageRequestState): UploadResultState = withContext(Dispatchers.IO) {
        core.topics().uploadImage(input)
    }

    suspend fun lookupUploadUrls(shortUrls: List<String>): List<ResolvedUploadUrlState> = withContext(Dispatchers.IO) {
        core.topics().lookupUploadUrls(shortUrls)
    }

    suspend fun fetchPostReplies(postId: ULong, after: UInt? = 1u): List<TopicPostState> = withContext(Dispatchers.IO) {
        core.topics().fetchPostReplies(postId, after)
    }

    suspend fun fetchPostReplyIds(postId: ULong): List<ULong> = withContext(Dispatchers.IO) {
        core.topics().fetchPostReplyIds(postId)
    }

    suspend fun fetchPostReplyHistory(postId: ULong): List<TopicPostState> = withContext(Dispatchers.IO) {
        core.topics().fetchPostReplyHistory(postId)
    }

    suspend fun likePost(postId: ULong): PostReactionUpdateState? = withContext(Dispatchers.IO) {
        val update = core.topics().likePost(postId)
        persistCurrentSession()
        update
    }

    suspend fun unlikePost(postId: ULong): PostReactionUpdateState? = withContext(Dispatchers.IO) {
        val update = core.topics().unlikePost(postId)
        persistCurrentSession()
        update
    }

    suspend fun togglePostReaction(postId: ULong, reactionId: String): PostReactionUpdateState =
        withContext(Dispatchers.IO) {
            val update = core.topics().togglePostReaction(postId, reactionId)
            persistCurrentSession()
            update
        }

    suspend fun fetchReactionUsers(postId: ULong): List<ReactionUsersGroupState> =
        withContext(Dispatchers.IO) {
            core.topics().fetchReactionUsers(postId)
        }

    suspend fun votePoll(postId: ULong, pollName: String, options: List<String>): PollState =
        withContext(Dispatchers.IO) {
            val poll = core.topics().votePoll(postId, pollName, options)
            persistCurrentSession()
            poll
        }

    suspend fun unvotePoll(postId: ULong, pollName: String): PollState = withContext(Dispatchers.IO) {
        val poll = core.topics().unvotePoll(postId, pollName)
        persistCurrentSession()
        poll
    }

    suspend fun voteTopic(topicId: ULong): VoteResponseState = withContext(Dispatchers.IO) {
        val response = core.topics().voteTopic(topicId)
        persistCurrentSession()
        response
    }

    suspend fun unvoteTopic(topicId: ULong): VoteResponseState = withContext(Dispatchers.IO) {
        val response = core.topics().unvoteTopic(topicId)
        persistCurrentSession()
        response
    }

    suspend fun fetchTopicVoters(topicId: ULong): List<VotedUserState> = withContext(Dispatchers.IO) {
        core.topics().fetchTopicVoters(topicId)
    }

    suspend fun deletePost(postId: ULong) = withContext(Dispatchers.IO) {
        core.topics().deletePost(postId)
        persistCurrentSession()
    }

    suspend fun recoverPost(postId: ULong) = withContext(Dispatchers.IO) {
        core.topics().recoverPost(postId)
        persistCurrentSession()
    }

    suspend fun acceptSolution(postId: ULong) = withContext(Dispatchers.IO) {
        core.topics().acceptSolution(postId)
        persistCurrentSession()
    }

    suspend fun unacceptSolution(postId: ULong) = withContext(Dispatchers.IO) {
        core.topics().unacceptSolution(postId)
        persistCurrentSession()
    }

    suspend fun flagPost(input: PostFlagRequestState) = withContext(Dispatchers.IO) {
        core.topics().flagPost(input)
        persistCurrentSession()
    }

    suspend fun fetchPostActionTypes(): List<PostActionTypeState> = withContext(Dispatchers.IO) {
        core.topics().fetchPostActionTypes()
    }

    suspend fun fetchUserProfile(username: String): UserProfileState = withContext(Dispatchers.IO) {
        core.user().fetchUserProfile(username)
    }

    suspend fun fetchUserSummary(username: String): UserSummaryState = withContext(Dispatchers.IO) {
        core.user().fetchUserSummary(username)
    }

    suspend fun fetchUserReactions(
        username: String,
        beforeReactionUserId: ULong? = null,
    ): UserReactionsState = withContext(Dispatchers.IO) {
        core.user().fetchUserReactions(username, beforeReactionUserId)
    }

    suspend fun fetchFollowing(username: String): List<FollowUserState> = withContext(Dispatchers.IO) {
        core.user().fetchFollowing(username)
    }

    suspend fun fetchFollowers(username: String): List<FollowUserState> = withContext(Dispatchers.IO) {
        core.user().fetchFollowers(username)
    }

    suspend fun followUser(username: String) = withContext(Dispatchers.IO) {
        core.user().followUser(username)
    }

    suspend fun unfollowUser(username: String) = withContext(Dispatchers.IO) {
        core.user().unfollowUser(username)
    }

    suspend fun setUserNotificationLevel(
        username: String,
        notificationLevel: String,
        expiringAt: String? = null,
    ) = withContext(Dispatchers.IO) {
        core.user().setUserNotificationLevel(username, notificationLevel, expiringAt)
        persistCurrentSession()
    }

    suspend fun awaitPreloadedData() {
        withContext(Dispatchers.IO) {
            core.session().awaitPreloadedData()
            persistCurrentSession()
        }
    }

    suspend fun ensurePreloadedDataLoaded() {
        withContext(Dispatchers.IO) {
            core.session().ensurePreloadedDataLoaded()
            persistCurrentSession()
        }
    }

    fun currentUserDefaults(): CurrentUserSnapshotState? {
        return try { core.session().currentUserSnapshot() } catch (_: Exception) { null }
    }

    fun cachedUser(): CurrentUserSnapshotState? {
        return try { core.session().cachedUser() } catch (_: Exception) { null }
    }

    fun determineLoginState(): LoginStateDeterminationState {
        return try { core.session().determineLoginState() } catch (_: Exception) {
            LoginStateDeterminationState.NotLoggedIn
        }
    }

    fun currentHomeTopicListScope(): HomeTopicListScopeState {
        return core.session().currentHomeTopicListScope()
    }

    fun setCurrentHomeTopicListScope(scope: HomeTopicListScopeState): HomeTopicListScopeState {
        return core.session().setCurrentHomeTopicListScope(scope)
    }

    suspend fun determineLoginStateWithProbe(): LoginStateDeterminationState {
        return withContext(Dispatchers.IO) {
            try {
                core.session().determineLoginStateWithProbe().also {
                    persistCurrentSession()
                }
            } catch (_: Exception) {
                LoginStateDeterminationState.NetworkErrorPreserveState
            }
        }
    }

    suspend fun triggerAppStateRefresh(trigger: RefreshTriggerState) = withContext(Dispatchers.IO) {
        core.session().triggerAppStateRefresh(trigger)
        persistCurrentSession()
    }

    suspend fun triggerAppStateRefresh(
        trigger: RefreshTriggerState,
        handler: AppStateRefreshHandler,
    ) = withContext(Dispatchers.IO) {
        core.session().triggerAppStateRefreshWithHandler(trigger, handler)
        persistCurrentSession()
    }

    private fun topicTrackingStateMetaForMessageBus(): Map<String, Long>? {
        val raw = runCatching { core.session().snapshot().bootstrap.topicTrackingStateMeta }
            .getOrNull()
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: return null
        val json = runCatching { JSONObject(raw) }.getOrNull() ?: return null
        val keys = json.keys()
        val result = LinkedHashMap<String, Long>()
        while (keys.hasNext()) {
            val key = keys.next()
            when (val value = json.opt(key)) {
                is Number -> result[key] = value.toLong()
                is String -> value.toLongOrNull()?.let { result[key] = it }
            }
        }
        return result.takeIf { it.isNotEmpty() }
    }

    suspend fun clearPersistedSession() = withContext(Dispatchers.IO) {
        core.session().clearSessionPath(sessionFile.absolutePath)
    }

    companion object {
        fun defaultWorkspacePath(context: Context): String {
            return File(context.filesDir, "fire").absolutePath
        }

        fun defaultSessionFilePath(context: Context): String {
            return File(defaultWorkspacePath(context), "session.json").absolutePath
        }
    }
}

data class FireCapturedLoginState(
    val currentUrl: String?,
    val username: String?,
    val csrfToken: String?,
    val homeHtml: String?,
    val browserUserAgent: String?,
    val cookies: List<PlatformCookieState>,
)
