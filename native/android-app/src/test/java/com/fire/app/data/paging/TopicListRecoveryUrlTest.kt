package com.fire.app.data.paging

import org.junit.Assert.assertEquals
import org.junit.Test
import uniffi.fire_uniffi_types.TopicListKindState

class TopicListRecoveryUrlTest {
    @Test
    fun htmlUrl_mapsGlobalLatestJsonToLatestHtml() {
        val url = TopicListRecoveryUrl.htmlUrl(
            baseUrl = "https://linux.do/",
            kind = TopicListKindState.LATEST,
            page = null,
            categorySlug = null,
            categoryId = null,
            parentCategorySlug = null,
            tag = null,
            additionalTags = emptyList(),
            matchAllTags = false,
        )

        assertEquals("https://linux.do/latest", url)
    }

    @Test
    fun htmlUrl_mapsCategoryFilterToCategoryHtmlRoute() {
        val url = TopicListRecoveryUrl.htmlUrl(
            baseUrl = "https://linux.do",
            kind = TopicListKindState.NEW,
            page = 2u,
            categorySlug = "rust",
            categoryId = 99uL,
            parentCategorySlug = "dev",
            tag = null,
            additionalTags = emptyList(),
            matchAllTags = false,
        )

        assertEquals("https://linux.do/c/dev/rust/99/l/new?page=2", url)
    }

    @Test
    fun htmlUrl_mapsTagFilterToTagHtmlRoute() {
        val url = TopicListRecoveryUrl.htmlUrl(
            baseUrl = "https://linux.do",
            kind = TopicListKindState.TOP,
            page = null,
            categorySlug = null,
            categoryId = null,
            parentCategorySlug = null,
            tag = "swift",
            additionalTags = emptyList(),
            matchAllTags = false,
        )

        assertEquals("https://linux.do/tag/swift/l/top", url)
    }

    @Test
    fun htmlUrl_preservesCategoryTagQueryOnHtmlRoute() {
        val url = TopicListRecoveryUrl.htmlUrl(
            baseUrl = "https://linux.do",
            kind = TopicListKindState.LATEST,
            page = null,
            categorySlug = "dev",
            categoryId = 42uL,
            parentCategorySlug = null,
            tag = "swift",
            additionalTags = listOf("rust"),
            matchAllTags = true,
        )

        assertEquals(
            "https://linux.do/c/dev/42/l/latest?tags%5B%5D=swift&tags%5B%5D=rust&match_all_tags=true",
            url,
        )
    }
}
