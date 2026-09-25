package com.fire.app.push

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.net.toUri
import com.fire.app.MainActivity
import com.fire.app.ui.topicdetail.TopicDetailActivity
import java.util.Locale
import kotlin.math.abs

data class FirePushNotification(
    val title: String,
    val body: String,
    val topicId: Long?,
    val topicTitle: String?,
    val postNumber: Int?,
    val username: String?,
    val deepLink: String?,
    val notificationId: Int,
) {
    fun contentIntent(context: Context): PendingIntent {
        val intent = targetIntent(context).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            context,
            notificationId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun targetIntent(context: Context): Intent {
        topicId?.let { id ->
            return TopicDetailActivity.createIntent(
                context = context,
                topicId = id,
                topicTitle = topicTitle ?: title,
                targetPostNumber = postNumber ?: -1,
            )
        }

        targetUri()?.let { uri ->
            topicRouteFrom(uri)?.let { route ->
                return TopicDetailActivity.createIntent(
                    context = context,
                    topicId = route.topicId,
                    targetPostNumber = route.postNumber ?: -1,
                )
            }
            profileUsernameFrom(uri)?.let { user ->
                return Intent(Intent.ACTION_VIEW, Uri.parse("fire://profile/${Uri.encode(user)}"))
                    .setPackage(context.packageName)
            }
            if (uri.scheme == "fire") {
                return Intent(Intent.ACTION_VIEW, uri).setPackage(context.packageName)
            }
            if (uri.scheme == null && uri.host == null) {
                return Intent(context, MainActivity::class.java)
            }
            return Intent(Intent.ACTION_VIEW, uri)
        }

        username?.let { user ->
            return Intent(Intent.ACTION_VIEW, Uri.parse("fire://profile/${Uri.encode(user)}"))
                .setPackage(context.packageName)
        }

        return Intent(context, MainActivity::class.java)
    }

    private fun targetUri(): Uri? {
        val raw = deepLink?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        val uri = runCatching { raw.toUri() }.getOrNull() ?: return null
        return when {
            uri.scheme == "fire" -> uri
            isLinuxDoHttpUri(uri) -> uri
            isLinuxDoRelativeUri(uri) -> uri
            else -> null
        }
    }

    private fun profileUsernameFrom(uri: Uri): String? {
        if (uri.scheme == "fire" && (uri.host == "profile" || uri.host == "user")) {
            return uri.pathSegments.firstOrNull()?.trim()?.takeIf { it.isNotEmpty() }
        }
        if ((isLinuxDoHttpUri(uri) || isLinuxDoRelativeUri(uri)) && uri.pathSegments.firstOrNull() == "u") {
            return uri.pathSegments.getOrNull(1)?.trim()?.takeIf { it.isNotEmpty() }
        }
        return null
    }

    private fun topicRouteFrom(uri: Uri): TopicRoute? {
        if (uri.scheme == "fire" && uri.host == "topic") {
            val topicId = uri.pathSegments.getOrNull(0)?.toLongOrNull()?.takeIf { it > 0L }
                ?: return null
            val postNumber = uri.pathSegments.getOrNull(1)?.toIntOrNull()?.takeIf { it > 0 }
            return TopicRoute(topicId = topicId, postNumber = postNumber)
        }
        if (
            !(isLinuxDoHttpUri(uri) || isLinuxDoRelativeUri(uri)) ||
            uri.pathSegments.firstOrNull() != "t"
        ) {
            return null
        }
        val topicId = uri.pathSegments
            .firstNotNullOfOrNull { segment -> segment.toLongOrNull()?.takeIf { it > 0L } }
            ?: return null
        val postNumber = uri.pathSegments
            .dropWhile { it.toLongOrNull() != topicId }
            .drop(1)
            .firstOrNull()
            ?.toIntOrNull()
            ?.takeIf { it > 0 }
        return TopicRoute(topicId = topicId, postNumber = postNumber)
    }

    private fun isLinuxDoHttpUri(uri: Uri): Boolean {
        return (uri.scheme == "http" || uri.scheme == "https") &&
            uri.host?.lowercase(Locale.US)?.let { host ->
                host == "linux.do" || host.endsWith(".linux.do")
            } == true
    }

    private fun isLinuxDoRelativeUri(uri: Uri): Boolean {
        return uri.scheme == null &&
            uri.host == null &&
            uri.pathSegments.firstOrNull() in setOf("t", "u")
    }

    private data class TopicRoute(
        val topicId: Long,
        val postNumber: Int?,
    )
}

object FirePushPayloadParser {
    fun parse(
        data: Map<String, String>,
        notificationTitle: String?,
        notificationBody: String?,
    ): FirePushNotification? {
        val title = firstText(
            data,
            "title",
            "topic_title",
            "fancy_title",
            "subject",
            fallback = notificationTitle,
        ) ?: "Fire"
        val body = firstText(
            data,
            "body",
            "message",
            "excerpt",
            "text",
            fallback = notificationBody,
        ) ?: title
        if (title.isBlank() && body.isBlank()) return null

        val topicId = firstLong(data, "topic_id", "topicId")
        val postNumber = firstInt(data, "post_number", "postNumber")
        val username = firstText(data, "username", "display_username", "original_username")
        val deepLink = firstText(data, "deep_link", "deeplink", "url", "post_url", "topic_url")
        val stableSeed = firstText(data, "notification_id", "id", "message_id")
            ?: listOfNotNull(topicId?.toString(), postNumber?.toString(), username, title, body)
                .joinToString(":")

        return FirePushNotification(
            title = title.trim(),
            body = body.trim(),
            topicId = topicId,
            topicTitle = firstText(data, "topic_title", "fancy_title", fallback = title),
            postNumber = postNumber,
            username = username,
            deepLink = deepLink,
            notificationId = stableNotificationId(stableSeed),
        )
    }

    internal fun stableNotificationId(seed: String): Int {
        val hash = seed.ifBlank { "fire-push" }.hashCode()
        return hash.takeIf { it != Int.MIN_VALUE }?.let(::abs) ?: 0
    }

    private fun firstText(
        data: Map<String, String>,
        vararg keys: String,
        fallback: String? = null,
    ): String? {
        keys.forEach { key ->
            data[key]?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
        }
        return fallback?.trim()?.takeIf { it.isNotEmpty() }
    }

    private fun firstLong(data: Map<String, String>, vararg keys: String): Long? {
        keys.forEach { key ->
            data[key]?.trim()?.toLongOrNull()?.takeIf { it > 0L }?.let { return it }
        }
        return null
    }

    private fun firstInt(data: Map<String, String>, vararg keys: String): Int? {
        keys.forEach { key ->
            data[key]?.trim()?.toIntOrNull()?.takeIf { it > 0 }?.let { return it }
        }
        return null
    }
}
