package com.fire.app.ui.topicdetail

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class TopicTimingTracker(
    private val topicId: ULong,
    private val scope: CoroutineScope,
    private val reporter: suspend (
        topicId: ULong,
        topicTimeMs: UInt,
        timings: Map<UInt, UInt>,
    ) -> Boolean,
    private val clock: Clock = SystemClock,
    private val callbackDispatcher: CoroutineDispatcher = Dispatchers.Main.immediate,
    private val reportDispatcher: CoroutineDispatcher = Dispatchers.IO,
) {
    interface Clock {
        fun elapsedRealtimeMs(): Long
    }

    private object SystemClock : Clock {
        override fun elapsedRealtimeMs(): Long = android.os.SystemClock.elapsedRealtime()
    }

    private object Constants {
        const val TICK_INTERVAL_MS = 1_000L
        const val FLUSH_INTERVAL_MS = 60_000L
        const val IDLE_PAUSE_INTERVAL_MS = 180_000L
        const val MAX_TRACKED_POST_MS = 6 * 60 * 1_000L
        val FAILED_REPORT_BACKOFF_INTERVALS_MS = longArrayOf(
            60_000L,
            120_000L,
            300_000L,
            600_000L,
        )
    }

    private var tickJob: Job? = null
    private var lastTickAtMs = 0L
    private var lastInteractionAtMs = 0L
    private var lastFlushAtMs = 0L
    private var visiblePostNumbers: Set<UInt> = emptySet()
    private val pendingTimings = mutableMapOf<UInt, Long>()
    private val totalTimings = mutableMapOf<UInt, Long>()
    private var topicTimeMs = 0L
    private var failedReportCount = 0
    private var reportBlockedUntilMs: Long? = null
    private var isFlushing = false
    private var isSceneActive = true
    private var isRunning = false

    fun start() {
        if (isRunning) return

        val now = clock.elapsedRealtimeMs()
        isRunning = true
        isSceneActive = true
        lastTickAtMs = now
        lastInteractionAtMs = now
        lastFlushAtMs = now

        tickJob = scope.launch(callbackDispatcher) {
            while (true) {
                delay(Constants.TICK_INTERVAL_MS)
                tick()
            }
        }
    }

    fun stop() {
        if (!isRunning) return

        tickJob?.cancel()
        tickJob = null
        tick()
        flushIfNeeded()
        isRunning = false
        visiblePostNumbers = emptySet()
    }

    fun updateVisiblePostNumbers(postNumbers: Set<UInt>) {
        if (visiblePostNumbers == postNumbers) return
        visiblePostNumbers = postNumbers
        recordInteraction()
    }

    fun recordInteraction() {
        lastInteractionAtMs = clock.elapsedRealtimeMs()
    }

    fun setSceneActive(active: Boolean) {
        if (isSceneActive == active) return

        isSceneActive = active
        lastTickAtMs = clock.elapsedRealtimeMs()
        if (active) {
            lastInteractionAtMs = lastTickAtMs
        } else {
            flushIfNeeded()
        }
    }

    internal fun tick() {
        if (!isRunning) return

        val now = clock.elapsedRealtimeMs()
        val diffMs = (now - lastTickAtMs).coerceAtLeast(0L)
        lastTickAtMs = now

        if (diffMs <= 0L) return
        if (!isSceneActive) return
        if (now - lastInteractionAtMs > Constants.IDLE_PAUSE_INTERVAL_MS) return

        topicTimeMs = topicTimeMs.saturatingAdd(diffMs)
        for (postNumber in visiblePostNumbers) {
            val total = totalTimings[postNumber] ?: 0L
            val remaining = Constants.MAX_TRACKED_POST_MS - total
            if (remaining <= 0L) continue

            val trackedMs = diffMs.coerceAtMost(remaining)
            pendingTimings[postNumber] = (pendingTimings[postNumber] ?: 0L).saturatingAdd(trackedMs)
            totalTimings[postNumber] = total.saturatingAdd(trackedMs)
        }

        if (now - lastFlushAtMs >= Constants.FLUSH_INTERVAL_MS) {
            flushIfNeeded()
        }
    }

    internal fun flushIfNeeded() {
        val now = clock.elapsedRealtimeMs()
        lastFlushAtMs = now

        if (isFlushing || topicTimeMs <= 0L) return
        val blockedUntil = reportBlockedUntilMs
        if (blockedUntil != null && blockedUntil > now) return

        val normalizedTimings = pendingTimings
            .filterValues { it > 0L }
            .mapValues { (_, milliseconds) -> milliseconds.toUIntClamped() }
            .filterValues { it > 0u }
        if (normalizedTimings.isEmpty()) return

        val normalizedTopicTimeMs = topicTimeMs.toUIntClamped()
        if (normalizedTopicTimeMs == 0u) return
        val reportedTimingSnapshot = normalizedTimings
        val reportedTopicTimeMs = normalizedTopicTimeMs

        isFlushing = true
        scope.launch(reportDispatcher) {
            val didReport = runCatching {
                reporter(topicId, reportedTopicTimeMs, reportedTimingSnapshot)
            }.getOrDefault(false)

            withContext(callbackDispatcher) {
                isFlushing = false
                if (didReport) {
                    failedReportCount = 0
                    reportBlockedUntilMs = null
                    topicTimeMs = (topicTimeMs - reportedTopicTimeMs.toLong()).coerceAtLeast(0L)
                    for ((postNumber, milliseconds) in reportedTimingSnapshot) {
                        val remaining = (pendingTimings[postNumber] ?: 0L) - milliseconds.toLong()
                        if (remaining > 0L) {
                            pendingTimings[postNumber] = remaining
                        } else {
                            pendingTimings.remove(postNumber)
                        }
                    }
                    if (pendingTimings.isNotEmpty()) {
                        flushIfNeeded()
                    }
                } else {
                    recordFailedReport(clock.elapsedRealtimeMs())
                }
            }
        }
    }

    private fun recordFailedReport(now: Long) {
        val index = failedReportCount.coerceAtMost(Constants.FAILED_REPORT_BACKOFF_INTERVALS_MS.lastIndex)
        val interval = Constants.FAILED_REPORT_BACKOFF_INTERVALS_MS[index]
        failedReportCount = failedReportCount.saturatingAdd(1)
        reportBlockedUntilMs = now.saturatingAdd(interval)
    }
}

private fun Long.saturatingAdd(other: Long): Long {
    if (other <= 0L) return this
    val remaining = Long.MAX_VALUE - this
    return if (remaining < other) Long.MAX_VALUE else this + other
}

private fun Int.saturatingAdd(other: Int): Int {
    if (other <= 0) return this
    val remaining = Int.MAX_VALUE - this
    return if (remaining < other) Int.MAX_VALUE else this + other
}

private fun Long.toUIntClamped(): UInt {
    if (this <= 0L) return 0u
    return coerceAtMost(UInt.MAX_VALUE.toLong()).toUInt()
}
