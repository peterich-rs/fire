package com.fire.app.ui.topicdetail

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.fire.app.R
import java.time.Instant

data class BookmarkReminderRequest(
    val bookmarkableId: ULong,
    val bookmarkableType: String,
    val topicId: Long,
    val postNumber: Int,
    val title: String,
    val reminderAt: String?,
)

object BookmarkReminderScheduler {
    private const val CHANNEL_ID = "bookmark_reminders"
    private const val EXTRA_BOOKMARKABLE_ID = "com.fire.app.extra.BOOKMARKABLE_ID"
    private const val EXTRA_BOOKMARKABLE_TYPE = "com.fire.app.extra.BOOKMARKABLE_TYPE"
    private const val EXTRA_TOPIC_ID = "com.fire.app.extra.TOPIC_ID"
    private const val EXTRA_POST_NUMBER = "com.fire.app.extra.POST_NUMBER"
    private const val EXTRA_TITLE = "com.fire.app.extra.TITLE"

    fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            context.getString(R.string.bookmark_reminder_channel_name),
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = context.getString(R.string.bookmark_reminder_channel_description)
        }
        manager.createNotificationChannel(channel)
    }

    fun sync(context: Context, request: BookmarkReminderRequest) {
        val triggerAtMillis = triggerAtMillis(request.reminderAt)
        if (triggerAtMillis == null || triggerAtMillis <= System.currentTimeMillis()) {
            cancel(context, request.bookmarkableId, request.bookmarkableType)
            return
        }

        createNotificationChannel(context)
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        alarmManager.cancel(pendingIntent(context, request.bookmarkableId, request.bookmarkableType))
        alarmManager.set(
            AlarmManager.RTC_WAKEUP,
            triggerAtMillis,
            pendingIntent(context, request),
        )
    }

    fun cancel(context: Context, bookmarkableId: ULong, bookmarkableType: String) {
        context.getSystemService(AlarmManager::class.java).cancel(
            pendingIntent(context, bookmarkableId, bookmarkableType),
        )
    }

    fun notificationChannelId(): String = CHANNEL_ID

    private fun pendingIntent(context: Context, request: BookmarkReminderRequest): PendingIntent {
        val intent = Intent(context, BookmarkReminderReceiver::class.java).apply {
            putExtra(EXTRA_BOOKMARKABLE_ID, request.bookmarkableId.toLong())
            putExtra(EXTRA_BOOKMARKABLE_TYPE, request.bookmarkableType)
            putExtra(EXTRA_TOPIC_ID, request.topicId)
            putExtra(EXTRA_POST_NUMBER, request.postNumber)
            putExtra(EXTRA_TITLE, request.title)
        }
        return PendingIntent.getBroadcast(
            context,
            requestCode(request.bookmarkableId, request.bookmarkableType),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun pendingIntent(
        context: Context,
        bookmarkableId: ULong,
        bookmarkableType: String,
    ): PendingIntent {
        val intent = Intent(context, BookmarkReminderReceiver::class.java)
        return PendingIntent.getBroadcast(
            context,
            requestCode(bookmarkableId, bookmarkableType),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    internal fun requestCode(bookmarkableId: ULong, bookmarkableType: String): Int {
        var result = bookmarkableType.lowercase().hashCode()
        result = 31 * result + bookmarkableId.hashCode()
        return result
    }

    internal fun triggerAtMillis(reminderAt: String?): Long? =
        reminderAt
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?.let { runCatching { Instant.parse(it).toEpochMilli() }.getOrNull() }

    internal fun titleFrom(intent: Intent): String =
        intent.getStringExtra(EXTRA_TITLE)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: "Linux.do"

    internal fun topicIntentFrom(context: Context, intent: Intent): Intent? {
        val topicId = intent.getLongExtra(EXTRA_TOPIC_ID, -1L).takeIf { it > 0L } ?: return null
        val postNumber = intent.getIntExtra(EXTRA_POST_NUMBER, -1)
        return TopicDetailActivity.createIntent(
            context = context,
            topicId = topicId,
            topicTitle = titleFrom(intent),
            targetPostNumber = postNumber,
        )
    }

    internal fun notificationIdFrom(intent: Intent): Int {
        val bookmarkableId = intent.getLongExtra(EXTRA_BOOKMARKABLE_ID, 0L).toULong()
        val bookmarkableType = intent.getStringExtra(EXTRA_BOOKMARKABLE_TYPE).orEmpty()
        return requestCode(bookmarkableId, bookmarkableType)
    }
}

class BookmarkReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        BookmarkReminderScheduler.createNotificationChannel(context)
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        val openIntent = BookmarkReminderScheduler.topicIntentFrom(context, intent)
        val pendingIntent = openIntent?.let {
            PendingIntent.getActivity(
                context,
                BookmarkReminderScheduler.notificationIdFrom(intent),
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val notification = NotificationCompat.Builder(
            context,
            BookmarkReminderScheduler.notificationChannelId(),
        )
            .setSmallIcon(R.drawable.ic_notifications)
            .setContentTitle(context.getString(R.string.bookmark_reminder_notification_title))
            .setContentText(BookmarkReminderScheduler.titleFrom(intent))
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .bigText(BookmarkReminderScheduler.titleFrom(intent)),
            )
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()

        NotificationManagerCompat.from(context).notify(
            BookmarkReminderScheduler.notificationIdFrom(intent),
            notification,
        )
    }
}
