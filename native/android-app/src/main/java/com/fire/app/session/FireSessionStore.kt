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
import uniffi.fire_uniffi_session.LoginSyncState
import uniffi.fire_uniffi_session.PlatformCookieState
import uniffi.fire_uniffi_session.SessionState
import uniffi.fire_uniffi_topics.TopicDetailQueryState
import uniffi.fire_uniffi_topics.TopicDetailState
import uniffi.fire_uniffi_topics.TopicListQueryState
import uniffi.fire_uniffi_topics.TopicPostState
import uniffi.fire_uniffi_types.TopicListState

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

    suspend fun refreshCsrfTokenIfNeeded(): SessionState = withContext(Dispatchers.IO) {
        val current = core.session().snapshot()
        if (current.cookies.csrfToken != null) {
            return@withContext current
        }

        val refreshed = core.session().refreshCsrfToken()
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

    suspend fun markNotificationRead(id: ULong): NotificationCenterState =
        withContext(Dispatchers.IO) {
            core.notifications().markNotificationRead(id)
        }

    suspend fun markAllNotificationsRead(): NotificationCenterState =
        withContext(Dispatchers.IO) {
            core.notifications().markAllNotificationsRead()
        }

    suspend fun restoreSessionJson(json: String): SessionState = withContext(Dispatchers.Default) {
        val restored = core.session().restoreSessionJson(json)
        persistCurrentSession()
        restored
    }

    suspend fun logout(): SessionState = withContext(Dispatchers.IO) {
        val state = core.session().logoutRemote(true)
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

    suspend fun fetchTopicPosts(topicId: ULong, postIds: List<ULong>): List<TopicPostState> = withContext(Dispatchers.IO) {
        core.topics().fetchTopicPosts(topicId, postIds)
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
