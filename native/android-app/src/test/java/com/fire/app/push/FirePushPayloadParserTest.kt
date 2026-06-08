package com.fire.app.push

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test

class FirePushPayloadParserTest {
    @Test
    fun parse_prefersDiscourseAlertFieldsAndRoutesToTopic() {
        val notification = FirePushPayloadParser.parse(
            data = mapOf(
                "topic_id" to "123",
                "post_number" to "4",
                "topic_title" to "Fire alert",
                "excerpt" to "New reply",
                "username" to "alice",
                "notification_id" to "9001",
            ),
            notificationTitle = null,
            notificationBody = null,
        )

        requireNotNull(notification)
        assertEquals("Fire alert", notification.title)
        assertEquals("New reply", notification.body)
        assertEquals(123L, notification.topicId)
        assertEquals(4, notification.postNumber)
        assertEquals("alice", notification.username)
        assertEquals(
            FirePushPayloadParser.stableNotificationId("9001"),
            notification.notificationId,
        )
    }

    @Test
    fun parse_usesFirebaseNotificationFallbacksWhenDataIsSparse() {
        val notification = FirePushPayloadParser.parse(
            data = emptyMap(),
            notificationTitle = "Mention",
            notificationBody = "alice mentioned you",
        )

        requireNotNull(notification)
        assertEquals("Mention", notification.title)
        assertEquals("alice mentioned you", notification.body)
        assertNull(notification.topicId)
        assertNull(notification.postNumber)
    }

    @Test
    fun stableNotificationId_isDeterministicAndSeparatesSeeds() {
        assertEquals(
            FirePushPayloadParser.stableNotificationId("123:4"),
            FirePushPayloadParser.stableNotificationId("123:4"),
        )
        assertNotEquals(
            FirePushPayloadParser.stableNotificationId("123:4"),
            FirePushPayloadParser.stableNotificationId("123:5"),
        )
    }

    @Test
    fun parse_keepsSafeLinuxDoDeepLinksForTapRouting() {
        val notification = FirePushPayloadParser.parse(
            data = mapOf(
                "title" to "Reply",
                "post_url" to "/t/fire/123/4",
            ),
            notificationTitle = null,
            notificationBody = null,
        )

        requireNotNull(notification)
        assertEquals("/t/fire/123/4", notification.deepLink)
    }
}
