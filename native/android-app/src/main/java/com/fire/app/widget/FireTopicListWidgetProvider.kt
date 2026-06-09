package com.fire.app.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import com.fire.app.MainActivity
import com.fire.app.R
import com.fire.app.ui.topicdetail.TopicDetailActivity

class FireTopicListWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        updateWidgets(context, manager, appWidgetIds)
    }

    companion object {
        private val rowIds = listOf(
            FireWidgetTopicRowIds(
                container = R.id.widget_topic_row_1,
                title = R.id.widget_topic_title_1,
                meta = R.id.widget_topic_meta_1,
            ),
            FireWidgetTopicRowIds(
                container = R.id.widget_topic_row_2,
                title = R.id.widget_topic_title_2,
                meta = R.id.widget_topic_meta_2,
            ),
            FireWidgetTopicRowIds(
                container = R.id.widget_topic_row_3,
                title = R.id.widget_topic_title_3,
                meta = R.id.widget_topic_meta_3,
            ),
        )

        fun updateWidgets(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
            val snapshot = FireWidgetData.load(context)
            for (widgetId in appWidgetIds) {
                manager.updateAppWidget(widgetId, buildViews(context, snapshot))
            }
        }

        private fun buildViews(context: Context, snapshot: FireWidgetSnapshot): RemoteViews {
            return RemoteViews(context.packageName, R.layout.widget_topic_list).apply {
                setTextViewText(
                    R.id.widget_topic_header,
                    snapshot.username.takeIf { it.isNotBlank() } ?: context.getString(R.string.widget_topic_list_title),
                )
                setViewVisibility(
                    R.id.widget_topic_empty,
                    if (snapshot.topics.isEmpty()) View.VISIBLE else View.GONE,
                )
                rowIds.forEachIndexed { index, rowIds ->
                    val topic = snapshot.topics.getOrNull(index)
                    if (topic == null) {
                        setViewVisibility(rowIds.container, View.GONE)
                    } else {
                        setViewVisibility(rowIds.container, View.VISIBLE)
                        setTextViewText(rowIds.title, topic.title)
                        setTextViewText(rowIds.meta, topic.metaText(context))
                        setOnClickPendingIntent(
                            rowIds.container,
                            topicPendingIntent(context, topic.id, index),
                        )
                    }
                }
                setOnClickPendingIntent(R.id.widget_topic_root, mainActivityPendingIntent(context))
            }
        }

        private fun FireWidgetTopic.metaText(context: Context): String {
            return buildList {
                category.takeIf { it.isNotBlank() }?.let(::add)
                if (replyCount > 0u) {
                    add(context.getString(R.string.widget_topic_replies, replyCount.toString()))
                }
                if (likeCount > 0u) {
                    add(context.getString(R.string.widget_topic_likes, likeCount.toString()))
                }
                updatedAt?.let(::add)
            }.joinToString(" · ")
        }

        private fun topicPendingIntent(context: Context, topicId: ULong, index: Int): PendingIntent {
            val intent = TopicDetailActivity.createIntent(
                context = context,
                topicId = topicId.toLong(),
            ).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            return PendingIntent.getActivity(
                context,
                2000 + index,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun mainActivityPendingIntent(context: Context): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            return PendingIntent.getActivity(
                context,
                2001,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}

private data class FireWidgetTopicRowIds(
    val container: Int,
    val title: Int,
    val meta: Int,
)
