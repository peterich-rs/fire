package com.fire.app.ui.home

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.fire_uniffi_messagebus.MessageBusEventKindState
import uniffi.fire_uniffi_messagebus.MessageBusEventState
import uniffi.fire_uniffi_types.TopicListKindState

class HomeTopicListMessageBusRefreshControllerTest {
    @Test
    fun register_ignoresEventsForOtherTopicListKinds() {
        val controller = HomeTopicListMessageBusRefreshController()
        val scope = HomeTopicListRefreshScope(
            kind = TopicListKindState.LATEST,
            categoryId = null,
            tags = emptyList(),
        )

        val delay = controller.register(
            event = topicListEvent(kind = TopicListKindState.NEW),
            scope = scope,
            nowMs = 1_000,
            allowTopicScopedRefresh = true,
        )

        assertNull(delay)
        assertFalse(controller.takePendingRefresh(scope))
    }

    @Test
    fun register_debouncesLatestTopicScopedEvents() {
        val controller = HomeTopicListMessageBusRefreshController(
            debounceDelayMs = 1_500,
            minimumIntervalMs = 30_000,
        )
        val scope = HomeTopicListRefreshScope(
            kind = TopicListKindState.LATEST,
            categoryId = null,
            tags = emptyList(),
        )

        val delay = controller.register(
            event = topicListEvent(kind = TopicListKindState.LATEST, topicId = 123uL),
            scope = scope,
            nowMs = 1_000,
            allowTopicScopedRefresh = true,
        )

        assertEquals(1_500L, delay)
        assertTrue(controller.takePendingRefresh(scope))
    }

    @Test
    fun register_rateLimitsAfterCompletedRefresh() {
        val controller = HomeTopicListMessageBusRefreshController(
            debounceDelayMs = 1_500,
            minimumIntervalMs = 30_000,
        )
        val scope = HomeTopicListRefreshScope(
            kind = TopicListKindState.LATEST,
            categoryId = null,
            tags = emptyList(),
        )

        controller.markRefreshCompleted(scope, nowMs = 10_000)
        val delay = controller.register(
            event = topicListEvent(kind = TopicListKindState.LATEST, topicId = 123uL),
            scope = scope,
            nowMs = 11_000,
            allowTopicScopedRefresh = true,
        )

        assertEquals(29_000L, delay)
    }

    @Test
    fun register_treatsFilteredScopesAsFullRefreshes() {
        val controller = HomeTopicListMessageBusRefreshController()
        val scope = HomeTopicListRefreshScope(
            kind = TopicListKindState.LATEST,
            categoryId = 2uL,
            tags = listOf("swift"),
        )

        val delay = controller.register(
            event = topicListEvent(kind = TopicListKindState.LATEST, topicId = 123uL),
            scope = scope,
            nowMs = 1_000,
            allowTopicScopedRefresh = false,
        )

        assertEquals(1_500L, delay)
        assertTrue(controller.takePendingRefresh(scope))
    }

    private fun topicListEvent(
        kind: TopicListKindState,
        topicId: ULong? = null,
    ): MessageBusEventState {
        return MessageBusEventState(
            channel = when (kind) {
                TopicListKindState.LATEST -> "/latest"
                TopicListKindState.NEW -> "/new"
                else -> "/latest"
            },
            messageId = 1,
            kind = MessageBusEventKindState.TOPIC_LIST,
            topicListKind = kind,
            topicId = topicId,
            notificationUserId = null,
            messageType = "latest",
            detailEventType = null,
            reloadTopic = false,
            refreshStream = false,
            allUnreadNotificationsCount = null,
            unreadNotifications = null,
            unreadHighPriorityNotifications = null,
            payloadJson = null,
        )
    }
}
