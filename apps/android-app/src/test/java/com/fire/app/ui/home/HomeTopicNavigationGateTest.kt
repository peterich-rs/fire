package com.fire.app.ui.home

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HomeTopicNavigationGateTest {
    @Test
    fun tryBeginOpeningTopicDetail_allowsOnlyOneOpenUntilReset() {
        val gate = HomeTopicNavigationGate()

        assertTrue(gate.tryBeginOpeningTopicDetail())
        assertFalse(gate.tryBeginOpeningTopicDetail())

        gate.reset()

        assertTrue(gate.tryBeginOpeningTopicDetail())
    }
}
