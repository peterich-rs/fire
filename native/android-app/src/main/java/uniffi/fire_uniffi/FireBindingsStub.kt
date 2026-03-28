package uniffi.fire_uniffi

import org.json.JSONObject
import java.io.File

enum class LoginPhaseState {
    Anonymous,
    CookiesCaptured,
    BootstrapCaptured,
    Ready,
}

data class PlatformCookieState(
    val name: String,
    val value: String,
    val domain: String?,
    val path: String?,
)

data class CookieState(
    val tToken: String? = null,
    val forumSession: String? = null,
    val cfClearance: String? = null,
    val csrfToken: String? = null,
)

data class BootstrapState(
    val baseUrl: String,
    val discourseBaseUri: String? = null,
    val sharedSessionKey: String? = null,
    val currentUsername: String? = null,
    val longPollingBaseUrl: String? = null,
    val turnstileSitekey: String? = null,
    val topicTrackingStateMeta: String? = null,
    val preloadedJson: String? = null,
    val hasPreloadedData: Boolean = false,
)

data class SessionReadinessState(
    val hasLoginCookie: Boolean = false,
    val hasForumSession: Boolean = false,
    val hasCloudflareClearance: Boolean = false,
    val hasCsrfToken: Boolean = false,
    val hasCurrentUser: Boolean = false,
    val hasPreloadedData: Boolean = false,
    val hasSharedSessionKey: Boolean = false,
    val canReadAuthenticatedApi: Boolean = false,
    val canWriteAuthenticatedApi: Boolean = false,
    val canOpenMessageBus: Boolean = false,
)

data class SessionState(
    val cookies: CookieState,
    val bootstrap: BootstrapState,
    val readiness: SessionReadinessState,
    val loginPhase: LoginPhaseState,
    val hasLoginSession: Boolean,
)

data class LoginSyncState(
    val currentUrl: String?,
    val username: String?,
    val csrfToken: String?,
    val homeHtml: String?,
    val cookies: List<PlatformCookieState>,
)

class FireCoreHandle(baseUrl: String?) {
    private val resolvedBaseUrl = baseUrl ?: "https://linux.do"
    private var sessionState = placeholderState(resolvedBaseUrl)

    fun snapshot(): SessionState = sessionState

    fun syncLoginContext(context: LoginSyncState): SessionState {
        var cookies = sessionState.cookies
        context.cookies.forEach { cookie ->
            cookies = when (cookie.name) {
                "_t" -> cookies.copy(tToken = cookie.value)
                "_forum_session" -> cookies.copy(forumSession = cookie.value)
                "cf_clearance" -> cookies.copy(cfClearance = cookie.value)
                else -> cookies
            }
        }
        if (context.csrfToken != null) {
            cookies = cookies.copy(csrfToken = context.csrfToken)
        }

        var bootstrap = sessionState.bootstrap.copy(currentUsername = context.username ?: sessionState.bootstrap.currentUsername)
        if (!context.homeHtml.isNullOrEmpty()) {
            bootstrap = bootstrap.copy(
                preloadedJson = context.homeHtml,
                hasPreloadedData = true,
            )
        }

        sessionState = deriveState(cookies, bootstrap)
        return sessionState
    }

    fun refreshBootstrap(): SessionState {
        val bootstrap = sessionState.bootstrap.copy(
            currentUsername = sessionState.bootstrap.currentUsername ?: "guest",
            hasPreloadedData = true,
        )
        sessionState = deriveState(sessionState.cookies, bootstrap)
        return sessionState
    }

    fun refreshCsrfToken(): SessionState {
        val cookies = sessionState.cookies.copy(
            csrfToken = sessionState.cookies.csrfToken ?: "stub-csrf-token",
        )
        sessionState = deriveState(cookies, sessionState.bootstrap)
        return sessionState
    }

    fun exportSessionJson(): String {
        return sessionState.toJson().toString()
    }

    fun restoreSessionJson(json: String): SessionState {
        sessionState = jsonToSession(JSONObject(json))
        return sessionState
    }

    fun saveSessionToPath(path: String) {
        val file = File(path)
        file.parentFile?.mkdirs()
        file.writeText(exportSessionJson())
    }

    fun loadSessionFromPath(path: String): SessionState {
        val file = File(path)
        sessionState = jsonToSession(JSONObject(file.readText()))
        return sessionState
    }

    fun clearSessionPath(path: String) {
        File(path).delete()
    }

    fun logoutRemote(preserveCfClearance: Boolean): SessionState {
        val clearance = if (preserveCfClearance) sessionState.cookies.cfClearance else null
        sessionState = deriveState(
            CookieState(cfClearance = clearance),
            BootstrapState(baseUrl = resolvedBaseUrl),
        )
        return sessionState
    }

    private fun placeholderState(baseUrl: String): SessionState {
        return SessionState(
            cookies = CookieState(),
            bootstrap = BootstrapState(baseUrl = baseUrl),
            readiness = SessionReadinessState(),
            loginPhase = LoginPhaseState.Anonymous,
            hasLoginSession = false,
        )
    }

    private fun deriveState(cookies: CookieState, bootstrap: BootstrapState): SessionState {
        val hasLoginCookie = !cookies.tToken.isNullOrEmpty()
        val hasForumSession = !cookies.forumSession.isNullOrEmpty()
        val hasCsrfToken = !cookies.csrfToken.isNullOrEmpty()
        val hasCurrentUser = !bootstrap.currentUsername.isNullOrEmpty()
        val hasSharedSessionKey = !bootstrap.sharedSessionKey.isNullOrEmpty()
        val canRead = hasLoginCookie && hasForumSession
        val canWrite = canRead && hasCsrfToken
        val canOpenMessageBus = canRead && hasSharedSessionKey

        val readiness = SessionReadinessState(
            hasLoginCookie = hasLoginCookie,
            hasForumSession = hasForumSession,
            hasCloudflareClearance = !cookies.cfClearance.isNullOrEmpty(),
            hasCsrfToken = hasCsrfToken,
            hasCurrentUser = hasCurrentUser,
            hasPreloadedData = bootstrap.hasPreloadedData,
            hasSharedSessionKey = hasSharedSessionKey,
            canReadAuthenticatedApi = canRead,
            canWriteAuthenticatedApi = canWrite,
            canOpenMessageBus = canOpenMessageBus,
        )

        val phase = when {
            !hasLoginCookie -> LoginPhaseState.Anonymous
            !canRead || !hasCurrentUser -> LoginPhaseState.CookiesCaptured
            !canWrite || !bootstrap.hasPreloadedData -> LoginPhaseState.BootstrapCaptured
            else -> LoginPhaseState.Ready
        }

        return SessionState(
            cookies = cookies,
            bootstrap = bootstrap,
            readiness = readiness,
            loginPhase = phase,
            hasLoginSession = hasLoginCookie,
        )
    }

    private fun SessionState.toJson(): JSONObject {
        return JSONObject()
            .put("cookies", JSONObject()
                .put("tToken", cookies.tToken)
                .put("forumSession", cookies.forumSession)
                .put("cfClearance", cookies.cfClearance)
                .put("csrfToken", cookies.csrfToken))
            .put("bootstrap", JSONObject()
                .put("baseUrl", bootstrap.baseUrl)
                .put("discourseBaseUri", bootstrap.discourseBaseUri)
                .put("sharedSessionKey", bootstrap.sharedSessionKey)
                .put("currentUsername", bootstrap.currentUsername)
                .put("longPollingBaseUrl", bootstrap.longPollingBaseUrl)
                .put("turnstileSitekey", bootstrap.turnstileSitekey)
                .put("topicTrackingStateMeta", bootstrap.topicTrackingStateMeta)
                .put("preloadedJson", bootstrap.preloadedJson)
                .put("hasPreloadedData", bootstrap.hasPreloadedData))
        }

    private fun jsonToSession(json: JSONObject): SessionState {
        val cookiesJson = json.optJSONObject("cookies") ?: JSONObject()
        val bootstrapJson = json.optJSONObject("bootstrap") ?: JSONObject()

        return deriveState(
            cookies = CookieState(
                tToken = cookiesJson.optNullableString("tToken"),
                forumSession = cookiesJson.optNullableString("forumSession"),
                cfClearance = cookiesJson.optNullableString("cfClearance"),
                csrfToken = cookiesJson.optNullableString("csrfToken"),
            ),
            bootstrap = BootstrapState(
                baseUrl = bootstrapJson.optString("baseUrl", resolvedBaseUrl),
                discourseBaseUri = bootstrapJson.optNullableString("discourseBaseUri"),
                sharedSessionKey = bootstrapJson.optNullableString("sharedSessionKey"),
                currentUsername = bootstrapJson.optNullableString("currentUsername"),
                longPollingBaseUrl = bootstrapJson.optNullableString("longPollingBaseUrl"),
                turnstileSitekey = bootstrapJson.optNullableString("turnstileSitekey"),
                topicTrackingStateMeta = bootstrapJson.optNullableString("topicTrackingStateMeta"),
                preloadedJson = bootstrapJson.optNullableString("preloadedJson"),
                hasPreloadedData = bootstrapJson.optBoolean("hasPreloadedData", false),
            ),
        )
    }

    private fun JSONObject.optNullableString(key: String): String? {
        if (isNull(key)) return null
        return optString(key).takeIf { it.isNotEmpty() }
    }
}
