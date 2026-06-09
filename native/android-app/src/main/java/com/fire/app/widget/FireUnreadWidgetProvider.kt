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

class FireUnreadWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        updateWidgets(context, manager, appWidgetIds)
    }

    companion object {
        fun updateWidgets(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
            val snapshot = FireWidgetData.load(context)
            for (widgetId in appWidgetIds) {
                manager.updateAppWidget(widgetId, buildViews(context, snapshot))
            }
        }

        private fun buildViews(context: Context, snapshot: FireWidgetSnapshot): RemoteViews {
            return RemoteViews(context.packageName, R.layout.widget_unread).apply {
                val unread = snapshot.unreadCount.toInt()
                setTextViewText(R.id.widget_unread_count, unread.toString())
                setTextViewText(
                    R.id.widget_unread_label,
                    context.resources.getQuantityString(R.plurals.widget_unread_count, unread, unread),
                )
                setViewVisibility(R.id.widget_unread_empty, if (unread == 0) View.VISIBLE else View.GONE)
                setOnClickPendingIntent(R.id.widget_unread_root, mainActivityPendingIntent(context, "notifications"))
            }
        }

        private fun mainActivityPendingIntent(context: Context, host: String): PendingIntent {
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setClass(context, MainActivity::class.java)
                data = android.net.Uri.parse("fire://$host")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            return PendingIntent.getActivity(
                context,
                1001,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}
