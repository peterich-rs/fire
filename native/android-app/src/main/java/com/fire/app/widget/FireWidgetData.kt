package com.fire.app.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import com.fire.app.TopicPresentation
import org.json.JSONArray
import org.json.JSONObject
import uniffi.fire_uniffi_notifications.NotificationCenterState
import uniffi.fire_uniffi_session.SessionState
import uniffi.fire_uniffi_types.TopicRowState

data class FireWidgetTopic(
    val id: ULong,
    val title: String,
    val category: String,
    val replyCount: UInt,
    val likeCount: UInt,
    val updatedAt: String?,
)

data class FireWidgetSnapshot(
    val unreadCount: UInt,
    val username: String,
    val topics: List<FireWidgetTopic>,
    val updatedAtEpochMs: Long,
)

object FireWidgetData {
    private const val PREFS_NAME = "fire_widget_prefs"
    private const val KEY_UNREAD_COUNT = "unread_count"
    private const val KEY_USERNAME = "username"
    private const val KEY_TOPIC_TITLES = "topic_titles"
    private const val KEY_UPDATED_AT = "updated_at"
    private const val MAX_TOPICS = 5

    fun updateTopicRows(context: Context, rows: List<TopicRowState>, session: SessionState?) {
        val snapshot = load(context)
        val categories = session?.bootstrap?.categories.orEmpty()
        val topics = rows.take(MAX_TOPICS).map { row ->
            val category = row.topic.categoryId?.let { categoryId ->
                categories.firstOrNull { it.id == categoryId }?.name?.takeIf(String::isNotBlank)
            } ?: row.topic.categoryId?.let { "Category #$it" }.orEmpty()
            FireWidgetTopic(
                id = row.topic.id,
                title = row.topic.title,
                category = category,
                replyCount = row.topic.replyCount,
                likeCount = row.topic.likeCount,
                updatedAt = TopicPresentation.formatTimestamp(row.activityTimestampUnixMs),
            )
        }
        saveAndRefresh(
            context = context,
            snapshot = snapshot.copy(
                username = session?.bootstrap?.currentUsername.orEmpty(),
                topics = topics,
                updatedAtEpochMs = System.currentTimeMillis(),
            ),
        )
    }

    fun updateNotificationState(context: Context, state: NotificationCenterState, session: SessionState?) {
        val snapshot = load(context)
        saveAndRefresh(
            context = context,
            snapshot = snapshot.copy(
                unreadCount = state.counters.allUnread,
                username = session?.bootstrap?.currentUsername ?: snapshot.username,
                updatedAtEpochMs = System.currentTimeMillis(),
            ),
        )
    }

    fun load(context: Context): FireWidgetSnapshot {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return FireWidgetSnapshot(
            unreadCount = prefs.getLong(KEY_UNREAD_COUNT, 0L).toUInt(),
            username = prefs.getString(KEY_USERNAME, "").orEmpty(),
            topics = decodeTopics(prefs.getString(KEY_TOPIC_TITLES, "[]").orEmpty()),
            updatedAtEpochMs = prefs.getLong(KEY_UPDATED_AT, 0L),
        )
    }

    private fun saveAndRefresh(context: Context, snapshot: FireWidgetSnapshot) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putLong(KEY_UNREAD_COUNT, snapshot.unreadCount.toLong())
            .putString(KEY_USERNAME, snapshot.username)
            .putString(KEY_TOPIC_TITLES, encodeTopics(snapshot.topics))
            .putLong(KEY_UPDATED_AT, snapshot.updatedAtEpochMs)
            .apply()
        refreshWidgets(context)
    }

    private fun refreshWidgets(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        manager.getAppWidgetIds(ComponentName(context, FireUnreadWidgetProvider::class.java))
            .takeIf { it.isNotEmpty() }
            ?.let { FireUnreadWidgetProvider.updateWidgets(context, manager, it) }
        manager.getAppWidgetIds(ComponentName(context, FireTopicListWidgetProvider::class.java))
            .takeIf { it.isNotEmpty() }
            ?.let { FireTopicListWidgetProvider.updateWidgets(context, manager, it) }
    }

    private fun encodeTopics(topics: List<FireWidgetTopic>): String {
        val array = JSONArray()
        topics.forEach { topic ->
            array.put(
                JSONObject()
                    .put("id", topic.id.toString())
                    .put("title", topic.title)
                    .put("category", topic.category)
                    .put("replyCount", topic.replyCount.toLong())
                    .put("likeCount", topic.likeCount.toLong())
                    .put("updatedAt", topic.updatedAt),
            )
        }
        return array.toString()
    }

    private fun decodeTopics(rawValue: String): List<FireWidgetTopic> {
        return runCatching {
            val array = JSONArray(rawValue)
            (0 until array.length()).mapNotNull { index ->
                val item = array.optJSONObject(index) ?: return@mapNotNull null
                FireWidgetTopic(
                    id = item.optString("id").toULongOrNull() ?: return@mapNotNull null,
                    title = item.optString("title"),
                    category = item.optString("category"),
                    replyCount = item.optLong("replyCount", 0L).toUInt(),
                    likeCount = item.optLong("likeCount", 0L).toUInt(),
                    updatedAt = item.optString("updatedAt").takeIf { it.isNotBlank() && it != "null" },
                )
            }
        }.getOrDefault(emptyList())
    }
}
