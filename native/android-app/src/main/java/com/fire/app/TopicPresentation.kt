package com.fire.app

import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import uniffi.fire_uniffi.TopicCategoryState
import uniffi.fire_uniffi.TopicSummaryState
import uniffi.fire_uniffi.TopicTagState

fun TopicCategoryState.displayName(): String {
    return if (name.isBlank()) "Category #$id" else name
}

object TopicPresentation {
    private val displayFormatter: DateTimeFormatter =
        DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
            .withLocale(Locale.getDefault())
    private val brTagRegex = Regex("<br\\s*/?>", RegexOption.IGNORE_CASE)
    private val paragraphCloseRegex = Regex("</p>", RegexOption.IGNORE_CASE)
    private val listItemCloseRegex = Regex("</li>", RegexOption.IGNORE_CASE)
    private val htmlTagRegex = Regex("<[^>]+>")
    private val repeatedBlankLinesRegex = Regex("\n{3,}")
    private val repeatedSpacesRegex = Regex("[ \\t]{2,}")

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

    fun tagNames(tags: List<TopicTagState>): List<String> {
        return tags.mapNotNull { tag ->
            tag.name.takeIf { it.isNotBlank() } ?: tag.slug?.takeIf { it.isNotBlank() }
        }
    }

    fun plainTextFromHtml(rawHtml: String?): String {
        if (rawHtml.isNullOrBlank()) {
            return ""
        }

        val normalized = rawHtml
            .replace(brTagRegex, "\n")
            .replace(paragraphCloseRegex, "\n\n")
            .replace(listItemCloseRegex, "\n")
        val stripped = normalized.replace(htmlTagRegex, " ")
        return decodeCommonEntities(stripped)
            .replace("\r\n", "\n")
            .replace(repeatedBlankLinesRegex, "\n\n")
            .replace(repeatedSpacesRegex, " ")
            .trim()
    }

    private fun decodeCommonEntities(value: String): String {
        return value
            .replace("&nbsp;", " ")
            .replace("&#160;", " ")
            .replace("&amp;", "&")
            .replace("&quot;", "\"")
            .replace("&#34;", "\"")
            .replace("&#39;", "'")
            .replace("&#x27;", "'")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
    }
}
