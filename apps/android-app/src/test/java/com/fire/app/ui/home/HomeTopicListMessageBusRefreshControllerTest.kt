package com.fire.app.ui.home

import org.junit.Assert.assertEquals
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
        assertNull(controller.takePendingRefresh(scope))
    }

    @Test
    fun register_aggregatesLatestTopicScopedEvents() {
        val controller = HomeTopicListMessageBusRefreshController(
            debounceDelayMs = 1_500,
            minimumIntervalMs = 45_000,
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
        controller.register(
            event = topicListEvent(kind = TopicListKindState.LATEST, topicId = 456uL),
            scope = scope,
            nowMs = 1_100,
            allowTopicScopedRefresh = true,
        )

        assertEquals(1_500L, delay)
        val refresh = controller.takePendingRefresh(scope)
        assertTrue(refresh is HomeTopicListRefreshMode.Incremental)
        assertEquals(
            listOf(123uL, 456uL),
            (refresh as HomeTopicListRefreshMode.Incremental).topicIds,
        )
        assertNull(controller.takePendingRefresh(scope))
    }

    @Test
    fun register_rateLimitsAfterCompletedRefresh() {
        val controller = HomeTopicListMessageBusRefreshController(
            debounceDelayMs = 1_500,
            minimumIntervalMs = 45_000,
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

        assertEquals(44_000L, delay)
    }

    @Test
    fun register_ignoresFilteredScopesAndTrackingTypes() {
        val controller = HomeTopicListMessageBusRefreshController()
        val filtered = HomeTopicListRefreshScope(
            kind = TopicListKindState.LATEST,
            categoryId = 2uL,
            tags = listOf("swift"),
        )
        assertNull(
            controller.register(
                event = topicListEvent(kind = TopicListKindState.LATEST, topicId = 123uL),
                scope = filtered,
                nowMs = 1_000,
                allowTopicScopedRefresh = false,
            ),
        )

        val latest = HomeTopicListRefreshScope(
            kind = TopicListKindState.LATEST,
            categoryId = null,
            tags = emptyList(),
        )
        assertNull(
            controller.register(
                event = topicListEvent(
                    kind = TopicListKindState.LATEST,
                    topicId = 99uL,
                    messageType = "unread",
                ),
                scope = latest,
                nowMs = 1_000,
                allowTopicScopedRefresh = true,
            ),
        )
        assertNull(controller.takePendingRefresh(latest))
    }

    private fun topicListEvent(
        kind: TopicListKindState,
        topicId: ULong? = null,
        messageType: String = "latest",
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
            messageType = messageType,
            detailEventType = null,
            reloadTopic = false,
            refreshStream = false,
            allUnreadNotificationsCount = null,
            unreadHighPriorityNotifications = null,
            unreadNotifications = null,
            payloadJson = null,
        )
    }
}
