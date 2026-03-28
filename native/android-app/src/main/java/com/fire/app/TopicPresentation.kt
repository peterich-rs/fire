package com.fire.app

import org.json.JSONArray
import org.json.JSONObject
import java.net.URI
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import uniffi.fire_uniffi.TopicSummaryState

data class TopicCategoryPresentation(
    val id: ULong,
    val name: String,
    val slug: String,
    val parentCategoryId: ULong?,
    val colorHex: String?,
    val textColorHex: String?,
) {
    val displayName: String
        get() = if (name.isBlank()) "Category #$id" else name
}

object TopicPresentation {
    private val displayFormatter: DateTimeFormatter =
        DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
            .withLocale(Locale.getDefault())

    fun parseCategories(preloadedJson: String?): Map<ULong, TopicCategoryPresentation> {
        if (preloadedJson.isNullOrBlank()) {
            return emptyMap()
        }

        return runCatching {
            val root = JSONObject(preloadedJson)
            val categories = findCategories(root) ?: JSONArray()

            buildMap {
                for (index in 0 until categories.length()) {
                    val raw = categories.optJSONObject(index) ?: continue
                    val id = raw.optLong("id").takeIf { it > 0 }?.toULong() ?: continue
                    put(
                        id,
                        TopicCategoryPresentation(
                            id = id,
                            name = raw.optString("name"),
                            slug = raw.optString("slug"),
                            parentCategoryId = raw.optLong("parent_category_id")
                                .takeIf { it > 0 }
                                ?.toULong(),
                            colorHex = raw.optString("color").ifBlank { null },
                            textColorHex = raw.optString("text_color").ifBlank { null },
                        ),
                    )
                }
            }
        }.getOrDefault(emptyMap())
    }

    fun nextPage(moreTopicsUrl: String?): UInt? {
        if (moreTopicsUrl.isNullOrBlank()) {
            return null
        }

        val candidates = listOf(
            moreTopicsUrl,
            "https://linux.do$moreTopicsUrl",
        )

        return candidates.firstNotNullOfOrNull { candidate ->
            queryParameter(candidate, "page")?.toUIntOrNull()
        }
    }

    fun formatTimestamp(rawValue: String?): String? {
        if (rawValue.isNullOrBlank()) {
            return null
        }

        return runCatching {
            displayFormatter.format(OffsetDateTime.parse(rawValue))
        }.getOrElse { rawValue }
    }

    fun topicStatusLabels(topic: TopicSummaryState): List<String> {
        return buildList {
            if (topic.pinned) add("Pinned")
            if (topic.closed) add("Closed")
            if (topic.archived) add("Archived")
            if (topic.hasAcceptedAnswer) add("Solved")
            if (topic.unreadPosts > 0u) add("${topic.unreadPosts} unread")
            if (topic.newPosts > 0u) add("${topic.newPosts} new")
        }
    }

    private fun findCategories(root: JSONObject): JSONArray? {
        val site = root.optJSONObject("site")
        return when {
            site?.optJSONArray("categories") != null -> site.optJSONArray("categories")
            site?.optJSONObject("category_list")?.optJSONArray("categories") != null ->
                site.optJSONObject("category_list")?.optJSONArray("categories")
            root.optJSONArray("categories") != null -> root.optJSONArray("categories")
            root.optJSONObject("category_list")?.optJSONArray("categories") != null ->
                root.optJSONObject("category_list")?.optJSONArray("categories")
            else -> null
        }
    }

    private fun queryParameter(url: String, name: String): String? {
        val rawQuery = runCatching {
            URI(url).rawQuery
        }.getOrNull() ?: return null

        return rawQuery
            .split('&')
            .asSequence()
            .mapNotNull { segment ->
                val separatorIndex = segment.indexOf('=')
                if (separatorIndex < 0) {
                    return@mapNotNull null
                }

                val key = segment.substring(0, separatorIndex)
                val value = segment.substring(separatorIndex + 1)
                if (key == name) value else null
            }
            .firstOrNull()
    }
}
