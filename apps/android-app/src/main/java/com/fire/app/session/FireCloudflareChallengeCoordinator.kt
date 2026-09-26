package com.fire.app.session

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import java.lang.ref.WeakReference
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import uniffi.fire_uniffi_session.CloudflareChallengeHandler
import uniffi.fire_uniffi_session.CloudflareChallengeRequestState
import uniffi.fire_uniffi_session.CloudflareChallengeResultState

object FireCloudflareChallengePresentationGate {
    @Volatile
    var isPresentationInFlight: Boolean = false
        private set

    @Volatile
    internal var waitingJoiners: Int = 0
        private set

    private val lock = Any()
    private var inFlight: Session? = null

    private class Session {
        private val latch = CountDownLatch(1)
        @Volatile
        private var result: CloudflareChallengeResultState? = null

        fun complete(value: CloudflareChallengeResultState) {
            result = value
            latch.countDown()
        }

        fun await(): CloudflareChallengeResultState {
            latch.await(5, TimeUnit.MINUTES)
            return result ?: cancelledResult()
        }
    }

    fun runExclusive(block: () -> CloudflareChallengeResultState): CloudflareChallengeResultState {
        val join: Session?
        val owned: Session?
        synchronized(lock) {
            val current = inFlight
            if (current != null) {
                waitingJoiners += 1
                join = current
                owned = null
            } else {
                val session = Session()
                inFlight = session
                isPresentationInFlight = true
                join = null
                owned = session
            }
        }
        if (join != null) {
            return try {
                join.await()
            } finally {
                synchronized(lock) {
                    waitingJoiners -= 1
                }
            }
        }
        val session = checkNotNull(owned)
        return try {
            val result = block()
            session.complete(result)
            result
        } catch (error: Throwable) {
            session.complete(cancelledResult())
            throw error
        } finally {
            synchronized(lock) {
                if (inFlight === session) {
                    inFlight = null
                    isPresentationInFlight = false
                }
            }
        }
    }

    fun resetForTesting() {
        synchronized(lock) {
            inFlight?.complete(cancelledResult())
            inFlight = null
            isPresentationInFlight = false
            waitingJoiners = 0
        }
    }

    private fun cancelledResult(): CloudflareChallengeResultState {
        return CloudflareChallengeResultState(
            completed = false,
            userCancelled = false,
            freshCfClearance = null,
            cookies = emptyList(),
            browserUserAgent = null,
        )
    }
}

/**
 * UI seam for a Cloudflare challenge. The logic handler calls this only when a
 * new presentation is required. Joiners wait on the gate and never reach it.
 */
fun interface FireCloudflareChallengeUi {
    fun present(request: CloudflareChallengeRequestState): CloudflareChallengeResultState
}

/** Tracks the resumed activity so a challenge can overlay it instead of starting a new task. */
object FireForegroundActivity {
    private var resumed = WeakReference<Activity>(null)

    fun current(): Activity? = resumed.get()

    val callbacks = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityResumed(activity: Activity) {
            if (activity !is FireCloudflareChallengeActivity) {
                resumed = WeakReference(activity)
            }
        }

        override fun onActivityPaused(activity: Activity) {
            if (resumed.get() === activity) {
                resumed = WeakReference(null)
            }
        }

        override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
        override fun onActivityStarted(activity: Activity) = Unit
        override fun onActivityStopped(activity: Activity) = Unit
        override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
        override fun onActivityDestroyed(activity: Activity) = Unit
    }
}

class FireCloudflareChallengeRuntimeHandler(
    context: Context,
    private val ui: FireCloudflareChallengeUi = FireCloudflareChallengeDialogUi(context.applicationContext),
) : CloudflareChallengeHandler {
    override fun completeCloudflareChallenge(
        request: CloudflareChallengeRequestState,
    ): CloudflareChallengeResultState {
        if (!request.isForeground) {
            return softChallengeResult(userCancelled = false)
        }
        // Only the owner of the gate presents UI. Concurrent requests wait here.
        return FireCloudflareChallengePresentationGate.runExclusive {
            ui.present(request)
        }
    }
}

class FireCloudflareChallengeDialogUi(
    private val context: Context,
) : FireCloudflareChallengeUi {
    private val coordinator = FireCloudflareChallengeCoordinator(context.applicationContext)

    override fun present(request: CloudflareChallengeRequestState): CloudflareChallengeResultState {
        return coordinator.completeSynchronously(request)
    }
}

private fun softChallengeResult(userCancelled: Boolean): CloudflareChallengeResultState {
    return CloudflareChallengeResultState(
        completed = false,
        userCancelled = userCancelled,
        freshCfClearance = null,
        cookies = emptyList(),
        browserUserAgent = null,
    )
}

class FireCloudflareChallengeCoordinator(
    private val context: Context,
) {
    fun completeSynchronously(
        request: CloudflareChallengeRequestState,
    ): CloudflareChallengeResultState {
        // Background/silent traffic must not steal focus. Rust only starts a new
        // challenge for foreground requests; keep a host-side defensive gate.
        if (!request.isForeground) {
            return cancelledResult(userCancelled = false)
        }

        FireCfClearanceRefreshService.get(context).beginManualChallenge("manual_challenge_start")
        try {
            return presentChallenge(request)
        } finally {
            FireCfClearanceRefreshService.get(context).endManualChallenge("manual_challenge_end")
        }
    }

    private fun presentChallenge(
        request: CloudflareChallengeRequestState,
    ): CloudflareChallengeResultState {
        val token = UUID.randomUUID().toString()
        val pending = PendingChallenge()
        PendingChallenges.register(token, pending)
        val host = FireForegroundActivity.current()
        val intent = Intent(host ?: context, FireCloudflareChallengeActivity::class.java).apply {
            if (host == null) {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            putExtra(FireCloudflareChallengeActivity.EXTRA_PENDING_TOKEN, token)
            putExtra(
                FireCloudflareChallengeActivity.EXTRA_TARGET_URL,
                challengeUrl(request.originUrl),
            )
        }
        (host ?: context).startActivity(intent)

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
