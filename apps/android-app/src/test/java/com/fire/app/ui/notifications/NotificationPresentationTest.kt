package com.fire.app.ui.notifications

import org.junit.Assert.assertEquals
import org.junit.Test
import uniffi.fire_uniffi_notifications.NotificationDataState
import uniffi.fire_uniffi_notifications.NotificationItemState

class NotificationPresentationTest {

    @Test
    fun mentioned_usesChineseCopyWithTitle() {
        val item = notification(
            type = 1,
            username = "alice",
            title = "Hello Fire",
        )
        assertEquals("alice 提到了你「Hello Fire」", NotificationPresentation.displayDescription(item))
    }

    @Test
    fun followed_usesChineseCopy() {
        val item = notification(type = 800, username = "bob", title = null)
        assertEquals("bob 关注了你", NotificationPresentation.displayDescription(item))
    }

    @Test
    fun badge_usesChineseCopy() {
        val item = notification(
            type = 12,
            username = "system",
            title = null,
            badgeName = "常客",
        )
        assertEquals("你获得了徽章「常客」", NotificationPresentation.displayDescription(item))
    }

    private fun notification(
        type: Int,
        username: String,
        title: String?,
        badgeName: String? = null,
    ): NotificationItemState {
        return NotificationItemState(
            id = 1u,
            userId = null,
            notificationType = type,
            read = false,
            highPriority = false,
            createdAt = null,
            createdTimestampUnixMs = null,
            postNumber = null,
            topicId = null,
            slug = null,
            fancyTitle = title,
            actingUserAvatarTemplate = null,
            data = NotificationDataState(
                displayUsername = username,
                originalPostId = null,
                originalPostType = null,
                originalUsername = null,
                revisionNumber = null,
                topicTitle = title,
                badgeName = badgeName,
                badgeId = null,
                badgeSlug = null,
                groupName = null,
                inboxCount = null,
                count = null,
                username = username,
                username2 = null,
                avatarTemplate = null,
                excerpt = null,
                payloadJson = null,
            ),
        )
    }
}
