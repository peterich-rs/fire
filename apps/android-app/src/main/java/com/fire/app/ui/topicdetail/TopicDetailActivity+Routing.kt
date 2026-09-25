package com.fire.app.ui.topicdetail

import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.core.text.HtmlCompat
import androidx.lifecycle.lifecycleScope
import com.fire.app.R
import com.fire.app.richtext.FireCookedImage
import com.fire.app.ui.webview.FireInAppWebViewActivity
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_topics.TopicPostState

internal fun TopicDetailActivity.handleRichTextLink(rawUrl: String) {
    val uri = runCatching { Uri.parse(rawUrl) }.getOrNull() ?: return
    profileUsernameFromUri(uri)?.let { username ->
        showUserInfoSheet(username)
        return
    }
    topicRouteFromUri(uri)?.let { route ->
        TopicDetailActivity.start(
            context = this,
            topicId = route.first,
            targetPostNumber = route.second,
        )
        return
    }
    val url = uri.toString()
    if (url.startsWith("http://") || url.startsWith("https://")) {
        FireInAppWebViewActivity.start(this, url)
        return
    }
    runCatching {
        startActivity(Intent(Intent.ACTION_VIEW, uri))
    }
}

internal fun TopicDetailActivity.profileUsernameFromUri(uri: Uri): String? {
    if (uri.scheme == "fire" && (uri.host == "profile" || uri.host == "user")) {
        return uri.pathSegments.firstOrNull()
    }
    if ((uri.scheme == "http" || uri.scheme == "https") &&
        uri.host?.endsWith("linux.do") == true &&
        uri.pathSegments.firstOrNull() == "u"
    ) {
        return uri.pathSegments.getOrNull(1)
    }
    return null
}

internal fun TopicDetailActivity.topicRouteFromUri(uri: Uri): Pair<Long, Int>? {
    if (uri.scheme == "fire" && uri.host == "topic") {
        val topicId = uri.pathSegments.getOrNull(0)?.toLongOrNull()?.takeIf { it > 0 } ?: return null
        val postNumber = uri.pathSegments.getOrNull(1)?.toIntOrNull() ?: -1
        return topicId to postNumber
    }
    if ((uri.scheme != "http" && uri.scheme != "https") ||
        uri.host?.endsWith("linux.do") != true ||
        uri.pathSegments.firstOrNull() != "t"
    ) {
        return null
    }
    val tail = uri.pathSegments.drop(1)
    if (tail.size == 2) {
        val topicId = tail[0].toLongOrNull()?.takeIf { it > 0 }
        val postNumber = tail[1].toIntOrNull()
        if (topicId != null && postNumber != null) {
            return topicId to postNumber
        }
    }
    if (tail.size >= 3) {
        val postNumber = tail.last().toIntOrNull()
        val topicId = tail.getOrNull(tail.size - 2)?.toLongOrNull()?.takeIf { it > 0 }
        if (topicId != null && postNumber != null) {
            return topicId to postNumber
        }
    }
    val topicId = tail.lastOrNull()?.toLongOrNull()?.takeIf { it > 0 } ?: return null
    return topicId to -1
}

internal fun TopicDetailActivity.showImageViewer(image: FireCookedImage) {
    TopicImagePreviewDialogFragment
        .newInstance(image)
        .show(supportFragmentManager, "topic_image_preview")
}

internal fun TopicDetailActivity.showReplyContext(post: TopicPostState) {
    val currentRoute = route ?: return
    Toast.makeText(
        this,
        R.string.topic_detail_reply_context_loading,
        Toast.LENGTH_SHORT,
    ).show()
    lifecycleScope.launch {
        try {
            val history = if (post.replyToPostNumber != null) {
                sessionStore.fetchPostReplyHistory(post.id)
            } else {
                emptyList()
            }
            val directReplies = fetchDirectReplies(currentRoute.topicId.toULong(), post)
            val message = replyContextMessage(history, directReplies)
            AlertDialog.Builder(this@showReplyContext)
                .setTitle(
                    getString(
                        R.string.topic_detail_reply_context_title,
                        post.postNumber.toString(),
                    ),
                )
                .setMessage(message)
                .setPositiveButton(android.R.string.ok, null)
                .show()
        } catch (e: Exception) {
            Toast.makeText(
                this@showReplyContext,
                e.localizedMessage ?: getString(R.string.topic_detail_reply_context_empty),
                Toast.LENGTH_SHORT,
            ).show()
        }
    }
}

internal suspend fun TopicDetailActivity.fetchDirectReplies(
    topicId: ULong,
    post: TopicPostState,
): List<TopicPostState> {
    if (post.replyCount == 0u) {
        return emptyList()
    }
    val replyIds = sessionStore.fetchPostReplyIds(post.id)
        .filter { it > 0u }
        .distinct()
    if (replyIds.isEmpty()) {
        return emptyList()
    }

    return replyIds.chunked(TopicDetailActivity.REPLY_CONTEXT_POST_BATCH_SIZE).flatMap { batch ->
        sessionStore.fetchTopicPosts(topicId, batch)
    }
}

internal fun TopicDetailActivity.replyContextMessage(
    history: List<TopicPostState>,
    directReplies: List<TopicPostState>,
): String {
    if (history.isEmpty() && directReplies.isEmpty()) {
        return getString(R.string.topic_detail_reply_context_empty)
    }

    return buildString {
        if (history.isNotEmpty()) {
            appendLine(getString(R.string.topic_detail_reply_context_history))
            appendLine(history.joinToString("\n\n") { replyContextPostLine(it) })
        }
        if (directReplies.isNotEmpty()) {
            if (isNotEmpty()) appendLine()
            appendLine(getString(R.string.topic_detail_reply_context_direct))
            appendLine(directReplies.joinToString("\n\n") { replyContextPostLine(it) })
        }
    }.trim()
}

internal fun TopicDetailActivity.replyContextPostLine(post: TopicPostState): String {
    val author = post.name?.takeIf { it.isNotBlank() } ?: "@${post.username}"
    val body = post.presentation?.plainText().orEmpty()
        .lineSequence()
        .map { it.trim() }
        .filter { it.isNotEmpty() }
        .joinToString(" ")
        .take(180)
    return "#${post.postNumber} $author\n$body"
}

internal fun TopicDetailActivity.plainText(html: String): String {
    return HtmlCompat.fromHtml(html, HtmlCompat.FROM_HTML_MODE_LEGACY)
        .toString()
        .trim()
}
