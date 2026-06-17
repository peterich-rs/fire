package com.fire.app.session

import android.content.Context
import android.content.Intent
import android.net.Uri
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import uniffi.fire_uniffi_session.CloudflareChallengeHandler
import uniffi.fire_uniffi_session.CloudflareChallengeRequestState
import uniffi.fire_uniffi_session.CloudflareChallengeResultState

class FireCloudflareChallengeRuntimeHandler(
    context: Context,
) : CloudflareChallengeHandler {
    private val coordinator = FireCloudflareChallengeCoordinator(context.applicationContext)

    override fun completeCloudflareChallenge(
        request: CloudflareChallengeRequestState,
    ): CloudflareChallengeResultState {
        return coordinator.completeSynchronously(request)
    }
}

class FireCloudflareChallengeCoordinator(
    private val context: Context,
) {
    fun completeSynchronously(
        request: CloudflareChallengeRequestState,
    ): CloudflareChallengeResultState {
        val token = UUID.randomUUID().toString()
        val pending = PendingChallenge()
        PendingChallenges.register(token, pending)
        val intent = Intent(context, FireCloudflareChallengeActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            putExtra(FireCloudflareChallengeActivity.EXTRA_PENDING_TOKEN, token)
            putExtra(
                FireCloudflareChallengeActivity.EXTRA_TARGET_URL,
                challengeUrl(request.originUrl),
            )
        }
        context.startActivity(intent)

        val completed = pending.latch.await(5, TimeUnit.MINUTES)
        PendingChallenges.remove(token)
        return if (completed) pending.result else cancelledResult(userCancelled = false)
    }

    private fun cancelledResult(userCancelled: Boolean): CloudflareChallengeResultState {
        return CloudflareChallengeResultState(
            completed = false,
            userCancelled = userCancelled,
            freshCfClearance = null,
            cookies = emptyList(),
            browserUserAgent = null,
        )
    }

    private fun challengeUrl(originUrl: String?): String {
        val parsed = originUrl
            ?.takeIf { it.isNotBlank() }
            ?.let { runCatching { Uri.parse(it) }.getOrNull() }
            ?.takeIf { !it.scheme.isNullOrBlank() && !it.host.isNullOrBlank() }
            ?: return "https://linux.do/challenge"
        return parsed.buildUpon()
            .path("/challenge")
            .clearQuery()
            .fragment(null)
            .build()
            .toString()
    }
}

internal object PendingChallenges {
    private val entries = ConcurrentHashMap<String, PendingChallenge>()

    fun register(token: String, pending: PendingChallenge) {
        entries[token] = pending
    }

    fun remove(token: String) {
        entries.remove(token)
    }

    fun finish(token: String, result: CloudflareChallengeResultState) {
        entries.remove(token)?.complete(result)
    }
}

internal class PendingChallenge {
    val latch = CountDownLatch(1)
    @Volatile
    var result: CloudflareChallengeResultState = CloudflareChallengeResultState(
        completed = false,
        userCancelled = false,
        freshCfClearance = null,
        cookies = emptyList(),
        browserUserAgent = null,
    )

    fun complete(result: CloudflareChallengeResultState) {
        this.result = result
        latch.countDown()
    }
}
