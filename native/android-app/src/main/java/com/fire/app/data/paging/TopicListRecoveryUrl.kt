package com.fire.app.data.paging

import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import uniffi.fire_uniffi_types.TopicListKindState

internal object TopicListRecoveryUrl {
    private const val DEFAULT_BASE_URL = "https://linux.do"

    fun htmlUrl(
        baseUrl: String?,
        kind: TopicListKindState,
        page: UInt?,
        categorySlug: String?,
        categoryId: ULong?,
        parentCategorySlug: String?,
        tag: String?,
        additionalTags: List<String>,
        matchAllTags: Boolean,
    ): String {
        val base = normalizedBaseUrl(baseUrl)
        val queryItems = mutableListOf<Pair<String, String>>()
        val path = htmlPath(
            kind = kind,
            categorySlug = categorySlug,
            categoryId = categoryId,
            parentCategorySlug = parentCategorySlug,
            tag = tag,
        )
        if (page != null && page > 0u) {
            queryItems += "page" to page.toString()
        }

        val queryTags = queryTags(
            categorySlug = categorySlug,
            primaryTag = tag,
            additionalTags = additionalTags,
        )
        for (queryTag in queryTags) {
            queryItems += "tags[]" to queryTag
        }
        if (matchAllTags && queryTags.size > 1) {
            queryItems += "match_all_tags" to "true"
        }

        return buildString {
            append(base)
            append(path)
            if (queryItems.isNotEmpty()) {
                append("?")
                append(
                    queryItems.joinToString("&") { (name, value) ->
                        "${queryComponent(name)}=${queryComponent(value)}"
                    },
                )
            }
        }
    }

    private fun htmlPath(
        kind: TopicListKindState,
        categorySlug: String?,
        categoryId: ULong?,
        parentCategorySlug: String?,
        tag: String?,
    ): String {
        val filter = filterName(kind)
        val cleanCategorySlug = categorySlug.clean()
        if (cleanCategorySlug != null) {
            if (categoryId != null) {
                val cleanParentSlug = parentCategorySlug.clean()
                val categorySegments = buildList {
                    add("c")
                    if (cleanParentSlug != null) add(cleanParentSlug)
                    add(cleanCategorySlug)
                    add(categoryId.toString())
                    add("l")
                    add(filter)
                }
                return categorySegments.toPath()
            }
            return listOf("c", cleanCategorySlug).toPath()
        }

        val cleanTag = tag.clean()
        if (cleanTag != null) {
            return listOf("tag", cleanTag, "l", filter).toPath()
        }

        return when (kind) {
            TopicListKindState.PRIVATE_MESSAGES_INBOX -> "/my/messages"
            TopicListKindState.PRIVATE_MESSAGES_SENT -> "/my/messages/sent"
            else -> listOf(filter).toPath()
        }
    }

    private fun queryTags(
        categorySlug: String?,
        primaryTag: String?,
        additionalTags: List<String>,
    ): List<String> {
        val tags = mutableListOf<String>()
        val cleanPrimaryTag = primaryTag.clean()
        if (categorySlug.clean() != null && cleanPrimaryTag != null) {
            tags += cleanPrimaryTag
        }
        tags += additionalTags.mapNotNull { it.clean() }
        return tags
    }

    private fun filterName(kind: TopicListKindState): String = when (kind) {
        TopicListKindState.LATEST -> "latest"
        TopicListKindState.NEW -> "new"
        TopicListKindState.UNREAD -> "unread"
        TopicListKindState.UNSEEN -> "unseen"
        TopicListKindState.HOT -> "hot"
        TopicListKindState.TOP -> "top"
        TopicListKindState.PRIVATE_MESSAGES_INBOX -> "private-messages"
        TopicListKindState.PRIVATE_MESSAGES_SENT -> "private-messages-sent"
    }

    private fun normalizedBaseUrl(baseUrl: String?): String {
        val trimmed = baseUrl?.trim()?.takeIf { it.isNotEmpty() } ?: DEFAULT_BASE_URL
        return trimmed.trimEnd('/')
    }

    private fun String?.clean(): String? = this
        ?.trim()
        ?.takeIf { it.isNotEmpty() }

    private fun List<String>.toPath(): String =
        joinToString(separator = "/", prefix = "/") { pathSegment(it) }

    private fun pathSegment(value: String): String = encode(value)

    private fun queryComponent(value: String): String = encode(value)

    private fun encode(value: String): String =
        URLEncoder.encode(value, StandardCharsets.UTF_8.toString())
            .replace("+", "%20")
}
