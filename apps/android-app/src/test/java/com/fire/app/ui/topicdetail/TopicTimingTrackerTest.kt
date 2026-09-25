package com.fire.app.ui.topicdetail

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Test

class TopicTimingTrackerTest {
    @Test
    fun tick_accumulatesTopicAndVisiblePostTiming() = runBlocking {
        val clock = FakeClock()
        val reports = mutableListOf<TimingReport>()
        val scope = testScope()
        val tracker = tracker(
            clock = clock,
            scope = scope,
            reporter = { topicId, topicTimeMs, timings ->
                reports.add(TimingReport(topicId, topicTimeMs, timings))
                true
            },
        )

        tracker.start()
        tracker.updateVisiblePostNumbers(setOf(1u, 2u))
        clock.advance(1_250L)
        tracker.tick()
        tracker.flushIfNeeded()

        assertEquals(1, reports.size)
        assertEquals(TOPIC_ID, reports.first().topicId)
        assertEquals(1_250u, reports.first().topicTimeMs)
        assertEquals(mapOf(1u to 1_250u, 2u to 1_250u), reports.first().timings)

        tracker.stop()
        scope.cancel()
    }

    @Test
    fun sceneInactive_flushesAndPausesAccumulation() = runBlocking {
        val clock = FakeClock()
        val reports = mutableListOf<TimingReport>()
        val scope = testScope()
        val tracker = tracker(
            clock = clock,
            scope = scope,
            reporter = { topicId, topicTimeMs, timings ->
                reports.add(TimingReport(topicId, topicTimeMs, timings))
                true
            },
        )

        tracker.start()
        tracker.updateVisiblePostNumbers(setOf(3u))
        clock.advance(1_000L)
        tracker.tick()
        tracker.setSceneActive(false)

        clock.advance(2_000L)
        tracker.tick()
        tracker.flushIfNeeded()

        assertEquals(1, reports.size)
        assertEquals(1_000u, reports.first().topicTimeMs)
        assertEquals(mapOf(3u to 1_000u), reports.first().timings)

        tracker.stop()
        scope.cancel()
    }

    @Test
    fun rejectedReportRetainsPendingTimingsUntilBackoffExpires() = runBlocking {
        val clock = FakeClock()
        val reports = mutableListOf<TimingReport>()
        val scope = testScope()
        var acceptReports = false
        val tracker = tracker(
            clock = clock,
            scope = scope,
            reporter = { topicId, topicTimeMs, timings ->
                reports.add(TimingReport(topicId, topicTimeMs, timings))
                acceptReports
            },
        )

        tracker.start()
        tracker.updateVisiblePostNumbers(setOf(4u))
        clock.advance(1_000L)
        tracker.tick()
        tracker.flushIfNeeded()

        clock.advance(1_000L)
        tracker.tick()
        tracker.flushIfNeeded()

        acceptReports = true
        clock.advance(60_000L)
        tracker.tick()

        assertEquals(2, reports.size)
        assertEquals(mapOf(4u to 1_000u), reports.first().timings)
        assertEquals(62_000u, reports.last().topicTimeMs)
        assertEquals(mapOf(4u to 62_000u), reports.last().timings)

        tracker.stop()
        scope.cancel()
    }

    @Test
    fun postTimingIsCappedAcrossSession() = runBlocking {
        val clock = FakeClock()
        val reports = mutableListOf<TimingReport>()
        val scope = testScope()
        val tracker = tracker(
            clock = clock,
            scope = scope,
            reporter = { topicId, topicTimeMs, timings ->
                reports.add(TimingReport(topicId, topicTimeMs, timings))
                true
            },
        )

        tracker.start()
        tracker.updateVisiblePostNumbers(setOf(8u))
        repeat(10 * 60) {
            clock.advance(1_000L)
            tracker.recordInteraction()
            tracker.tick()
        }

        assertEquals(6, reports.size)
        assertEquals(360_000u, reports.sumOf { it.topicTimeMs.toLong() }.toUInt())
        assertEquals(360_000u, reports.sumOf { it.timings[8u]?.toLong() ?: 0L }.toUInt())

        tracker.stop()
        scope.cancel()
    }

    @Test
    fun successfulReportKeepsTimingsRecordedDuringInFlightReport() = runBlocking {
        val clock = FakeClock()
        val reports = mutableListOf<TimingReport>()
        val scope = testScope()
        val firstReportGate = CompletableDeferred<Unit>()
        val tracker = tracker(
            clock = clock,
            scope = scope,
            reporter = { topicId, topicTimeMs, timings ->
                reports.add(TimingReport(topicId, topicTimeMs, timings))
                if (reports.size == 1) {
                    firstReportGate.await()
                }
                true
            },
        )

        tracker.start()
        tracker.updateVisiblePostNumbers(setOf(9u))
        clock.advance(1_000L)
        tracker.tick()
        tracker.flushIfNeeded()

        clock.advance(500L)
        tracker.tick()
        tracker.stop()
        firstReportGate.complete(Unit)
        yield()

        assertEquals(2, reports.size)
        assertEquals(1_000u, reports.first().topicTimeMs)
        assertEquals(mapOf(9u to 1_000u), reports.first().timings)
        assertEquals(500u, reports.last().topicTimeMs)
        assertEquals(mapOf(9u to 500u), reports.last().timings)

        scope.cancel()
    }

    private fun tracker(
        clock: FakeClock,
        scope: CoroutineScope,
        reporter: suspend (ULong, UInt, Map<UInt, UInt>) -> Boolean,
    ): TopicTimingTracker {
        return TopicTimingTracker(
            topicId = TOPIC_ID,
            scope = scope,
            reporter = reporter,
            clock = clock,
            callbackDispatcher = Dispatchers.Unconfined,
            reportDispatcher = Dispatchers.Unconfined,
        )
    }

    private fun testScope(): CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)

    private data class TimingReport(
        val topicId: ULong,
        val topicTimeMs: UInt,
        val timings: Map<UInt, UInt>,
    )

    private class FakeClock : TopicTimingTracker.Clock {
        private var now = 0L

        override fun elapsedRealtimeMs(): Long = now

        fun advance(milliseconds: Long) {
            now += milliseconds
        }
    }

    private companion object {
        const val TOPIC_ID = 123uL
    }
}
