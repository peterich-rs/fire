package com.fire.app.data.paging

import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import uniffi.fire_uniffi_types.TopicListKindState

object TopicListRecoveryUrl {
    fun htmlUrl(
        baseUrl: String,
        kind: TopicListKindState,
        page: UInt?,
        categorySlug: String?,
        categoryId: ULong?,
        parentCategorySlug: String?,
        tag: String?,
        additionalTags: List<String>,
        matchAllTags: Boolean,
        topicIds: List<ULong> = emptyList(),
    ): String {
        val normalizedBaseUrl = normalizedRecoveryRootUrl(baseUrl)
        val filter = topicListFilterName(kind)
        val normalizedCategorySlug = normalizedTopicListSegment(categorySlug)
        val normalizedTag = normalizedTopicListSegment(tag)

        val path = when {
            normalizedCategorySlug != null -> buildString {
                append("c/")
                normalizedTopicListSegment(parentCategorySlug)?.let {
                    append(it)
                    append('/')
                }
                append(normalizedCategorySlug)
                categoryId?.let {
                    append('/')
                    append(it.toString())
                    append("/l/")
                    append(filter)
                }
            }
            normalizedTag != null -> "tag/$normalizedTag/l/$filter"
            else -> when (kind) {
                TopicListKindState.PRIVATE_MESSAGES_INBOX -> "my/messages"
                TopicListKindState.PRIVATE_MESSAGES_SENT -> "my/messages/sent"
                else -> if (topicIds.isEmpty()) filter else "latest"
            }
        }

        val queryItems = mutableListOf<Pair<String, String>>()
        if (page != null && page > 0u) {
            queryItems += "page" to page.toString()
        }
        val queryTags = topicListRecoveryQueryTags(
            categorySlug = normalizedCategorySlug,
            primaryTag = normalizedTag,
            additionalTags = additionalTags,
        )
        queryItems += queryTags.map { "tags[]" to it }
        if (matchAllTags && queryTags.size > 1) {
            queryItems += "match_all_tags" to "true"
        }

        val url = "$normalizedBaseUrl$path"
        return appendQueryItems(url, queryItems)
    }

    private fun normalizedRecoveryRootUrl(baseUrl: String): String {
        val trimmed = baseUrl.trim()
        val rawBaseUrl = if (trimmed.isEmpty()) "https://linux.do/" else trimmed
        return if (rawBaseUrl.endsWith("/")) rawBaseUrl else "$rawBaseUrl/"
    }

    private fun normalizedTopicListSegment(value: String?): String? {
        val trimmed = value?.trim().orEmpty()
        return trimmed.ifEmpty { null }
    }

    private fun topicListFilterName(kind: TopicListKindState): String = when (kind) {
        TopicListKindState.LATEST -> "latest"
        TopicListKindState.NEW -> "new"
        TopicListKindState.UNREAD -> "unread"
        TopicListKindState.UNSEEN -> "unseen"
        TopicListKindState.HOT -> "hot"
        TopicListKindState.TOP -> "top"
        TopicListKindState.PRIVATE_MESSAGES_INBOX -> "private-messages"
        TopicListKindState.PRIVATE_MESSAGES_SENT -> "private-messages-sent"
    }

    private fun topicListRecoveryQueryTags(
        categorySlug: String?,
        primaryTag: String?,
        additionalTags: List<String>,
    ): List<String> {
        val tags = mutableListOf<String>()
        if (categorySlug != null && primaryTag != null) {
            tags += primaryTag
        }
        tags += additionalTags.mapNotNull(::normalizedTopicListSegment)
        return tags
    }

    private fun appendQueryItems(
        url: String,
        queryItems: List<Pair<String, String>>,
    ): String {
        if (queryItems.isEmpty()) {
            return url
        }

        val query = queryItems.joinToString("&") { (name, value) ->
            "${name.urlEncode()}=${value.urlEncode()}"
        }
        return "$url?$query"
    }

    private fun String.urlEncode(): String =
        URLEncoder.encode(this, StandardCharsets.UTF_8)
}
