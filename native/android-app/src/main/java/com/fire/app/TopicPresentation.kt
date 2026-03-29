package com.fire.app

import org.json.JSONArray
import org.json.JSONObject
import java.net.URI
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import uniffi.fire_uniffi.TopicTagState
import uniffi.fire_uniffi.TopicPostState
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

data class TopicReplyPresentation(
    val post: TopicPostState,
    val depth: Int,
    val parentPostNumber: UInt?,
)

data class TopicReplySectionPresentation(
    val anchorPost: TopicPostState,
    val replies: List<TopicReplyPresentation>,
)

data class TopicThreadPresentation(
    val originalPost: TopicPostState?,
    val replySections: List<TopicReplySectionPresentation>,
)

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

    fun buildThreadPresentation(posts: List<TopicPostState>): TopicThreadPresentation {
        if (posts.isEmpty()) {
            return TopicThreadPresentation(originalPost = null, replySections = emptyList())
        }

        val originalPost = posts.minByOrNull { it.postNumber.toInt() }
            ?: return TopicThreadPresentation(originalPost = null, replySections = emptyList())
        val rootPostNumber = originalPost.postNumber
        val postsByNumber = posts.associateBy { it.postNumber }

        val childrenByParent = mutableMapOf<UInt, MutableList<TopicPostState>>()
        posts
            .asSequence()
            .filter { it.postNumber != rootPostNumber }
            .forEach { post ->
                val parentPostNumber = normalizedReplyTarget(post)
                if (parentPostNumber != null && parentPostNumber != post.postNumber) {
                    childrenByParent.getOrPut(parentPostNumber) { mutableListOf() }.add(post)
                }
            }

        val consumedPostNumbers = mutableSetOf(rootPostNumber)
        val replySections = mutableListOf<TopicReplySectionPresentation>()

        posts
            .asSequence()
            .filter { it.postNumber != rootPostNumber }
            .forEach { post ->
                if (post.postNumber in consumedPostNumbers) {
                    return@forEach
                }

                val normalizedParent = normalizedReplyTarget(post)
                val shouldStartSection = normalizedParent == null ||
                    normalizedParent == rootPostNumber ||
                    postsByNumber[normalizedParent] == null
                if (!shouldStartSection) {
                    return@forEach
                }

                consumedPostNumbers += post.postNumber
                val branchVisited = mutableSetOf(post.postNumber)
                replySections += TopicReplySectionPresentation(
                    anchorPost = post,
                    replies = flattenReplies(
                        parentPostNumber = post.postNumber,
                        depth = 1,
                        childrenByParent = childrenByParent,
                        consumedPostNumbers = consumedPostNumbers,
                        branchVisited = branchVisited,
                    ),
                )
            }

        posts
            .asSequence()
            .filter { it.postNumber != rootPostNumber && it.postNumber !in consumedPostNumbers }
            .forEach { post ->
                consumedPostNumbers += post.postNumber
                val branchVisited = mutableSetOf(post.postNumber)
                replySections += TopicReplySectionPresentation(
                    anchorPost = post,
                    replies = flattenReplies(
                        parentPostNumber = post.postNumber,
                        depth = 1,
                        childrenByParent = childrenByParent,
                        consumedPostNumbers = consumedPostNumbers,
                        branchVisited = branchVisited,
                    ),
                )
            }

        return TopicThreadPresentation(
            originalPost = originalPost,
            replySections = replySections,
        )
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

    private fun normalizedReplyTarget(post: TopicPostState): UInt? {
        val replyToPostNumber = post.replyToPostNumber ?: return null
        return replyToPostNumber.takeIf { it > 0u }
    }

    private fun flattenReplies(
        parentPostNumber: UInt,
        depth: Int,
        childrenByParent: Map<UInt, List<TopicPostState>>,
        consumedPostNumbers: MutableSet<UInt>,
        branchVisited: MutableSet<UInt>,
    ): List<TopicReplyPresentation> {
        val children = childrenByParent[parentPostNumber].orEmpty()
        return buildList {
            for (child in children) {
                if (child.postNumber in branchVisited) {
                    continue
                }

                consumedPostNumbers += child.postNumber
                add(
                    TopicReplyPresentation(
                        post = child,
                        depth = depth,
                        parentPostNumber = normalizedReplyTarget(child),
                    ),
                )

                branchVisited += child.postNumber
                addAll(
                    flattenReplies(
                        parentPostNumber = child.postNumber,
                        depth = depth + 1,
                        childrenByParent = childrenByParent,
                        consumedPostNumbers = consumedPostNumbers,
                        branchVisited = branchVisited,
                    ),
                )
                branchVisited -= child.postNumber
            }
        }
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
