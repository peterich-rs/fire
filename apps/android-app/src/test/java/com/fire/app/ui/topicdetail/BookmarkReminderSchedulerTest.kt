package com.fire.app.ui.topicdetail

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BookmarkReminderSchedulerTest {
    @Test
    fun triggerAtMillis_parsesIsoInstantAndRejectsBlankOrInvalidInput() {
        assertEquals(
            1_735_689_599_000L,
            BookmarkReminderScheduler.triggerAtMillis("2024-12-31T23:59:59Z"),
        )
        assertNull(BookmarkReminderScheduler.triggerAtMillis(" "))
        assertNull(BookmarkReminderScheduler.triggerAtMillis("not-a-date"))
    }

    @Test
    fun requestCode_isStableAndSeparatesBookmarkableTypes() {
        val topicCode = BookmarkReminderScheduler.requestCode(42uL, "Topic")

        assertEquals(topicCode, BookmarkReminderScheduler.requestCode(42uL, "topic"))
        assertNotEquals(topicCode, BookmarkReminderScheduler.requestCode(42uL, "Post"))
        assertNotEquals(topicCode, BookmarkReminderScheduler.requestCode(43uL, "Topic"))
    }
}
