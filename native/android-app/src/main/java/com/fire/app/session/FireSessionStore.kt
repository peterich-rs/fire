package com.fire.app.session

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import uniffi.fire_uniffi.FireAppCore
import uniffi.fire_uniffi_diagnostics.LogFileDetailState
import uniffi.fire_uniffi_diagnostics.LogFileSummaryState
import uniffi.fire_uniffi_diagnostics.NetworkTraceDetailState
import uniffi.fire_uniffi_diagnostics.NetworkTraceSummaryState
import uniffi.fire_uniffi_notifications.NotificationCenterState
import uniffi.fire_uniffi_notifications.NotificationListState
import uniffi.fire_uniffi_search.SearchQueryState
import uniffi.fire_uniffi_search.SearchResultState
import uniffi.fire_uniffi_session.LoginSyncState
import uniffi.fire_uniffi_session.PlatformCookieState
import uniffi.fire_uniffi_session.SessionState
import uniffi.fire_uniffi_topics.PollState
import uniffi.fire_uniffi_topics.PostActionTypeState
import uniffi.fire_uniffi_topics.PostFlagRequestState
import uniffi.fire_uniffi_topics.PostReactionUpdateState
import uniffi.fire_uniffi_topics.PostUpdateRequestState
import uniffi.fire_uniffi_topics.PrivateMessageCreateRequestState
import uniffi.fire_uniffi_topics.ReactionUsersGroupState
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

    suspend fun persistCurrentSession() = withContext(Dispatchers.IO) {
        sessionFile.parentFile?.mkdirs()
        core.session().saveSessionToPath(sessionFile.absolutePath)
    }

    fun workspacePath(): String = workspaceDir.absolutePath

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
        core.topics().fetchTopicList(query)
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

    suspend fun fetchTopicPosts(topicId: ULong, postIds: List<ULong>): List<TopicPostState> = withContext(Dispatchers.IO) {
        core.topics().fetchTopicPosts(topicId, postIds)
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
