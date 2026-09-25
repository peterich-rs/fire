package com.fire.app.ui.composer

import org.junit.Assert.assertEquals
import org.junit.Test

class MarkdownInsertionTest {
    @Test
    fun apply_wrapsSelectedText() {
        val result = MarkdownInsertion.apply(
            action = MarkdownFormatAction.BOLD,
            text = "hello world",
            selectionStart = 6,
            selectionEnd = 11,
        )

        assertEquals("hello **world**", result.text)
        assertEquals(8, result.selectionStart)
        assertEquals(13, result.selectionEnd)
    }

    @Test
    fun apply_createsOrderedListAcrossSelectedLines() {
        val result = MarkdownInsertion.apply(
            action = MarkdownFormatAction.ORDERED_LIST,
            text = "one\ntwo",
            selectionStart = 0,
            selectionEnd = 7,
        )

        assertEquals("1. one\n2. two", result.text)
        assertEquals(0, result.selectionStart)
        assertEquals(13, result.selectionEnd)
    }

    @Test
    fun apply_keepsCursorInsideLinkPlaceholder() {
        val result = MarkdownInsertion.apply(
            action = MarkdownFormatAction.LINK,
            text = "",
            selectionStart = 0,
            selectionEnd = 0,
        )

        assertEquals("[text](url)", result.text)
        assertEquals(1, result.selectionStart)
        assertEquals(5, result.selectionEnd)
    }

    @Test
    fun quoteMarkdown_buildsDiscourseQuoteBlockFromPlainText() {
        val quote = QuoteMarkdown.build(
            username = " alice \"fire\"\r\nnative ",
            postNumber = 7u,
            topicId = 42uL,
            plainText = "\nHello Fire\n\n",
        )

        assertEquals(
            "[quote=\"alice 'fire' native, post:7, topic:42\"]\nHello Fire\n[/quote]\n\n",
            quote,
        )
    }

    @Test
    fun quoteMarkdown_returnsNullForBlankPlainText() {
        val quote = QuoteMarkdown.build(
            username = "alice",
            postNumber = 7u,
            topicId = 42uL,
            plainText = " \n ",
        )

        assertEquals(null, quote)
    }

    @Test
    fun composerInitialBody_prependsInitialBodyToExistingDraftAndPlacesCursorAfterInitialBody() {
        val initial = "[quote=\"alice, post:7, topic:42\"]\nHello\n[/quote]\n\n"
        val result = ComposerInitialBody.merge(
            initialBody = initial,
            currentBody = "Existing draft",
        )

        assertEquals(
            initial + "Existing draft",
            result.text,
        )
        assertEquals(initial.length, result.selectionStart)
        assertEquals(initial.length, result.selectionEnd)
    }

    @Test
    fun composerInitialBody_doesNotDuplicateExistingInitialBody() {
        val initial = "[quote=\"alice, post:7, topic:42\"]\nHello\n[/quote]\n\n"
        val result = ComposerInitialBody.merge(
            initialBody = initial,
            currentBody = initial + "Existing draft",
        )

        assertEquals(initial + "Existing draft", result.text)
        assertEquals(initial.length, result.selectionStart)
        assertEquals(initial.length, result.selectionEnd)
    }

    @Test
    fun composerInitialBody_usesPreferredCursorInsideExistingInitialBody() {
        val initial = "[quote=\"alice, post:7, topic:42\"]\nHello\n[/quote]\n\nTyped draft"
        val cursor = initial.indexOf("Typed draft")
        val result = ComposerInitialBody.merge(
            initialBody = initial,
            currentBody = initial,
            preferredSelectionStart = cursor,
        )

        assertEquals(initial, result.text)
        assertEquals(cursor, result.selectionStart)
        assertEquals(cursor, result.selectionEnd)
    }
}
