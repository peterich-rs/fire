package com.fire.app.ui.home

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.fire_uniffi_types.TopicListKindState

class HomeScopePresentationTest {

    @Test
    fun defaultScope_usesAllAndLatest() {
        val presentation = HomeScopePresentation.make(
            kind = TopicListKindState.LATEST,
            categoryId = null,
            tags = emptyList(),
            categories = emptyList(),
        )
        assertEquals("全部", presentation.categoryPathTitle)
        assertEquals("最新", presentation.kindTitle)
        assertTrue(presentation.isDefaultScope)
        assertFalse(presentation.showsChildShortcutStrip)
    }

    @Test
    fun kindTitles_matchIos() {
        assertEquals("最新", TopicListKindState.LATEST.fireTitle())
        assertEquals("最新发布", TopicListKindState.NEW.fireTitle())
        assertEquals("未读", TopicListKindState.UNREAD.fireTitle())
        assertEquals("未看", TopicListKindState.UNSEEN.fireTitle())
        assertEquals("热门", TopicListKindState.HOT.fireTitle())
        assertEquals("精华", TopicListKindState.TOP.fireTitle())
    }
}
