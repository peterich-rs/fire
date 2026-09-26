package com.fire.app.session

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import uniffi.fire_uniffi_session.CloudflareChallengeResultState

class FireCloudflareChallengePresentationGateTest {
    @Before
    fun setUp() {
        FireCloudflareChallengePresentationGate.resetForTesting()
    }

    @After
    fun tearDown() {
        FireCloudflareChallengePresentationGate.resetForTesting()
    }

    @Test
    fun runExclusive_joinsConcurrentCallersWithoutSecondPresentation() {
        val started = CountDownLatch(1)
        val releaseOwner = CountDownLatch(1)
        val presentations = AtomicInteger(0)
        val executor = Executors.newFixedThreadPool(2)
        val shared = CloudflareChallengeResultState(
            completed = true,
            userCancelled = false,
            freshCfClearance = "joined",
            cookies = emptyList(),
            browserUserAgent = null,
        )

        val owner = executor.submit<CloudflareChallengeResultState> {
            FireCloudflareChallengePresentationGate.runExclusive {
                presentations.incrementAndGet()
                started.countDown()
                releaseOwner.await(2, TimeUnit.SECONDS)
                shared
            }
        }
        assertTrue(started.await(2, TimeUnit.SECONDS))
        assertTrue(FireCloudflareChallengePresentationGate.isPresentationInFlight)

        val joiner = executor.submit<CloudflareChallengeResultState> {
            FireCloudflareChallengePresentationGate.runExclusive {
                presentations.incrementAndGet()
                CloudflareChallengeResultState(
                    completed = false,
                    userCancelled = true,
                    freshCfClearance = "should-not-run",
                    cookies = emptyList(),
                    browserUserAgent = null,
                )
            }
        }
        assertTrue(awaitWaitingJoiners(1))

        releaseOwner.countDown()
        val ownerResult = owner.get(2, TimeUnit.SECONDS)
        val joinerResult = joiner.get(2, TimeUnit.SECONDS)
        executor.shutdownNow()

        assertEquals(1, presentations.get())
        assertEquals("joined", ownerResult.freshCfClearance)
        assertEquals("joined", joinerResult.freshCfClearance)
        assertFalse(FireCloudflareChallengePresentationGate.isPresentationInFlight)
    }

    @Test
    fun runExclusive_allowsSequentialPresentations() {
        val first = FireCloudflareChallengePresentationGate.runExclusive {
            CloudflareChallengeResultState(
                completed = true,
                userCancelled = false,
                freshCfClearance = "one",
                cookies = emptyList(),
                browserUserAgent = null,
            )
        }
        val second = FireCloudflareChallengePresentationGate.runExclusive {
            CloudflareChallengeResultState(
                completed = true,
                userCancelled = false,
                freshCfClearance = "two",
                cookies = emptyList(),
                browserUserAgent = null,
            )
        }
        assertEquals("one", first.freshCfClearance)
        assertEquals("two", second.freshCfClearance)
    }

    private fun awaitWaitingJoiners(count: Int): Boolean {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(2)
        while (System.nanoTime() < deadline) {
            if (FireCloudflareChallengePresentationGate.waitingJoiners >= count) {
                return true
            }
            Thread.sleep(5)
        }
        return FireCloudflareChallengePresentationGate.waitingJoiners >= count
    }
}
