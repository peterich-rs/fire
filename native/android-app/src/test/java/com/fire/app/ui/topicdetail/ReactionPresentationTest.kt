package com.fire.app.ui.topicdetail

import org.junit.Assert.assertEquals
import org.junit.Test

class ReactionPresentationTest {
    @Test
    fun fullOptions_preservesEnabledOrderAndAddsCurrentReaction() {
        val options = ReactionPresentation.fullOptions(
            reactionIds = listOf("heart", "laughing", "heart"),
            currentReactionId = "tada",
        )

        assertEquals(listOf("heart", "laughing", "tada"), options.map { it.id })
        assertEquals("❤️", options[0].symbol)
        assertEquals("😆", options[1].symbol)
        assertEquals("庆祝", options[2].label)
    }

    @Test
    fun filteredOptions_matchesIdLabelOrSymbol() {
        val options = ReactionPresentation.fullOptions(
            reactionIds = listOf("heart", "laughing", "thumbsup"),
            currentReactionId = null,
        )

        assertEquals(listOf("laughing"), ReactionPresentation.filteredOptions(options, "laugh").map { it.id })
        assertEquals(listOf("thumbsup"), ReactionPresentation.filteredOptions(options, "赞同").map { it.id })
        assertEquals(listOf("heart"), ReactionPresentation.filteredOptions(options, "❤️").map { it.id })
        assertEquals(options.map { it.id }, ReactionPresentation.filteredOptions(options, " ").map { it.id })
    }
}
