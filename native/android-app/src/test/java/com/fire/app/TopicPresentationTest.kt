package com.fire.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TopicPresentationTest {
    @Test
    fun parseCategories_readsSiteCategories() {
        val categories = TopicPresentation.parseCategories(
            """
            {
              "site": {
                "categories": [
                  {
                    "id": 7,
                    "name": "Rust",
                    "slug": "rust",
                    "parent_category_id": 2,
                    "color": "FFFFFF",
                    "text_color": "000000"
                  }
                ]
              }
            }
            """.trimIndent(),
        )

        assertEquals(1, categories.size)
        assertEquals("Rust", categories[7uL]?.name)
        assertEquals("rust", categories[7uL]?.slug)
        assertEquals(2uL, categories[7uL]?.parentCategoryId)
        assertEquals("FFFFFF", categories[7uL]?.colorHex)
        assertEquals("000000", categories[7uL]?.textColorHex)
    }

    @Test
    fun nextPage_readsRelativeAndAbsoluteMoreTopicsUrls() {
        assertEquals(3u, TopicPresentation.nextPage("/latest?page=3"))
        assertEquals(9u, TopicPresentation.nextPage("https://linux.do/latest?page=9"))
        assertNull(TopicPresentation.nextPage("/latest"))
        assertNull(TopicPresentation.nextPage(null))
    }
}
