package com.fire.app.session

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import uniffi.fire_uniffi.FireCoreHandle
import uniffi.fire_uniffi.LoginSyncState
import uniffi.fire_uniffi.LogFileDetailState
import uniffi.fire_uniffi.LogFileSummaryState
import uniffi.fire_uniffi.NetworkTraceDetailState
import uniffi.fire_uniffi.NetworkTraceSummaryState
import uniffi.fire_uniffi.NotificationCenterState
import uniffi.fire_uniffi.NotificationListState
import uniffi.fire_uniffi.PlatformCookieState
import uniffi.fire_uniffi.SessionState
import uniffi.fire_uniffi.TopicDetailQueryState
import uniffi.fire_uniffi.TopicDetailState
import uniffi.fire_uniffi.TopicListQueryState
import uniffi.fire_uniffi.TopicListState

class FireSessionStore(
    context: Context,
    baseUrl: String? = null,
    workspacePath: String? = null,
    sessionFilePath: String? = null,
) {
    private val workspaceDir: File
    private val core: FireCoreHandle
    private val sessionFile: File

    init {
        val resolvedWorkspacePath = workspacePath
            ?: sessionFilePath?.let { File(it).parentFile?.absolutePath }
            ?: defaultWorkspacePath(context)
        workspaceDir = File(resolvedWorkspacePath)
        core = FireCoreHandle(baseUrl, workspaceDir.absolutePath)
        sessionFile = File(sessionFilePath ?: core.resolveWorkspacePath("session.json"))
    }

    suspend fun snapshot(): SessionState = withContext(Dispatchers.Default) {
        core.snapshot()
    }

    suspend fun restorePersistedSessionIfAvailable(): SessionState? = withContext(Dispatchers.IO) {
        if (!sessionFile.exists()) {
            return@withContext null
        }
        core.loadSessionFromPath(sessionFile.absolutePath)
    }

    suspend fun syncLoginContext(captured: FireCapturedLoginState): SessionState =
        withContext(Dispatchers.Default) {
            val state = core.syncLoginContext(
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
        val current = core.snapshot()
        if (current.bootstrap.hasPreloadedData) {
            return@withContext current
        }

        val refreshed = core.refreshBootstrap()
        persistCurrentSession()
        refreshed
    }

    suspend fun refreshCsrfTokenIfNeeded(): SessionState = withContext(Dispatchers.IO) {
        val current = core.snapshot()
        if (current.cookies.csrfToken != null) {
            return@withContext current
        }

        val refreshed = core.refreshCsrfToken()
        persistCurrentSession()
        refreshed
    }

    suspend fun persistCurrentSession() = withContext(Dispatchers.IO) {
        sessionFile.parentFile?.mkdirs()
        core.saveSessionToPath(sessionFile.absolutePath)
    }

    fun workspacePath(): String = workspaceDir.absolutePath

    suspend fun listLogFiles(): List<LogFileSummaryState> =
        withContext(Dispatchers.IO) {
            core.listLogFiles()
        }

    suspend fun readLogFile(relativePath: String): LogFileDetailState =
        withContext(Dispatchers.IO) {
            core.readLogFile(relativePath)
        }

    suspend fun listNetworkTraces(limit: ULong = 200uL): List<NetworkTraceSummaryState> =
        withContext(Dispatchers.IO) {
            core.listNetworkTraces(limit)
        }

    suspend fun networkTraceDetail(traceId: ULong): NetworkTraceDetailState? =
        withContext(Dispatchers.IO) {
            core.networkTraceDetail(traceId)
        }

    suspend fun exportSessionJson(): String = withContext(Dispatchers.Default) {
        core.exportSessionJson()
    }

    suspend fun notificationState(): NotificationCenterState = withContext(Dispatchers.Default) {
        core.notificationState()
    }

    suspend fun fetchRecentNotifications(limit: UInt? = null): NotificationListState =
        withContext(Dispatchers.IO) {
            core.fetchRecentNotifications(limit)
        }

    suspend fun fetchNotifications(
        limit: UInt? = null,
        offset: UInt? = null,
    ): NotificationListState = withContext(Dispatchers.IO) {
        core.fetchNotifications(limit, offset)
    }

    suspend fun markNotificationRead(id: ULong): NotificationCenterState =
        withContext(Dispatchers.IO) {
            core.markNotificationRead(id)
        }

    suspend fun markAllNotificationsRead(): NotificationCenterState =
        withContext(Dispatchers.IO) {
            core.markAllNotificationsRead()
        }

    suspend fun restoreSessionJson(json: String): SessionState = withContext(Dispatchers.Default) {
        val restored = core.restoreSessionJson(json)
        persistCurrentSession()
        restored
    }

    suspend fun logout(): SessionState = withContext(Dispatchers.IO) {
        val state = core.logoutRemote(true)
        clearPersistedSession()
        state
    }

    suspend fun fetchTopicList(query: TopicListQueryState): TopicListState = withContext(Dispatchers.IO) {
        core.fetchTopicList(query)
    }

    suspend fun fetchTopicDetail(query: TopicDetailQueryState): TopicDetailState = withContext(Dispatchers.IO) {
        core.fetchTopicDetail(query)
    }

    suspend fun clearPersistedSession() = withContext(Dispatchers.IO) {
        core.clearSessionPath(sessionFile.absolutePath)
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
