package com.fire.app.ui.topicdetail

import android.Manifest
import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.view.View
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.core.content.ContextCompat
import com.fire.app.R
import com.fire.app.core.ext.dp
import uniffi.fire_uniffi_topics.TopicPostState
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

internal fun TopicDetailActivity.showPostBookmarkEditor(post: TopicPostState) {
    showBookmarkEditor(
        bookmarkableId = post.id,
        bookmarkableType = "Post",
        bookmarkId = post.bookmarkId,
        bookmarkName = post.bookmarkName,
        bookmarkReminderAt = post.bookmarkReminderAt,
        targetPostNumber = post.postNumber,
    )
}

internal fun TopicDetailActivity.showBookmarkEditor(
    bookmarkableId: ULong,
    bookmarkableType: String,
    bookmarkId: ULong?,
    bookmarkName: String?,
    bookmarkReminderAt: String?,
    targetPostNumber: UInt?,
) {
    val nameInput = EditText(this).apply {
        setText(bookmarkName.orEmpty())
        hint = getString(R.string.topic_detail_bookmark_name_hint)
        setSingleLine(true)
    }
    val reminderSelection = BookmarkReminderSelection.from(bookmarkReminderAt)
    val reminderToggle = androidx.appcompat.widget.SwitchCompat(this).apply {
        text = getString(R.string.topic_detail_bookmark_reminder_label)
        isChecked = reminderSelection.hasReminder
    }
    val reminderButton = TextView(this).apply {
        setPadding(0, dp(12), 0, dp(4))
        text = reminderSelection.displayText(this@showBookmarkEditor)
        setTextColor(getColor(R.color.fire_accent))
        setOnClickListener {
            showBookmarkReminderDatePicker(reminderSelection, this)
        }
    }
    reminderButton.visibility = if (reminderSelection.hasReminder) View.VISIBLE else View.GONE
    reminderToggle.setOnCheckedChangeListener { _, isChecked ->
        reminderSelection.hasReminder = isChecked
        if (isChecked && reminderSelection.dateTime == null) {
            reminderSelection.dateTime = ZonedDateTime.now().plusHours(1)
        }
        reminderButton.text = reminderSelection.displayText(this)
        reminderButton.visibility = if (isChecked) View.VISIBLE else View.GONE
    }
    val content = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(24), dp(8), dp(24), 0)
        addView(nameInput)
        addView(reminderToggle)
        addView(reminderButton)
    }

    val dialog = AlertDialog.Builder(this)
        .setTitle(
            if (bookmarkId == null) {
                R.string.topic_detail_bookmark_add_title
            } else {
                R.string.topic_detail_bookmark_edit_title
            },
        )
        .setView(content)
        .setPositiveButton(R.string.topic_detail_bookmark_save, null)
        .setNegativeButton(android.R.string.cancel, null)
        .apply {
            if (bookmarkId != null) {
                setNeutralButton(R.string.topic_detail_bookmark_delete, null)
            }
        }
        .create()
    dialog.setOnShowListener {
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
            val reminderAt = reminderSelection.reminderAt()
            val key = BookmarkReminderKey(bookmarkableId, bookmarkableType)
            pendingBookmarkReminders[key] = BookmarkReminderRequest(
                bookmarkableId = bookmarkableId,
                bookmarkableType = bookmarkableType,
                topicId = route?.topicId ?: -1L,
                postNumber = targetPostNumber?.toInt() ?: -1,
                title = bookmarkReminderTitle(bookmarkableType, targetPostNumber),
                reminderAt = reminderAt,
            )
            viewModel?.saveBookmark(
                bookmarkableId = bookmarkableId,
                bookmarkableType = bookmarkableType,
                bookmarkId = bookmarkId,
                name = nameInput.text.toString(),
                reminderAt = reminderAt,
                targetPostNumber = targetPostNumber,
            )
            dialog.dismiss()
        }
        if (bookmarkId != null) {
            dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener {
                viewModel?.deleteBookmark(
                    bookmarkId = bookmarkId,
                    bookmarkableId = bookmarkableId,
                    bookmarkableType = bookmarkableType,
                    targetPostNumber = targetPostNumber,
                )
                dialog.dismiss()
            }
        }
    }
    dialog.show()
}

internal fun TopicDetailActivity.showBookmarkReminderDatePicker(
    selection: BookmarkReminderSelection,
    target: TextView,
) {
    val current = selection.dateTime ?: ZonedDateTime.now().plusHours(1)
    DatePickerDialog(
        this,
        { _, year, month, dayOfMonth ->
            TimePickerDialog(
                this,
                { _, hourOfDay, minute ->
                    val selectedDateTime = current
                        .withYear(year)
                        .withMonth(month + 1)
                        .withDayOfMonth(dayOfMonth)
                        .withHour(hourOfDay)
                        .withMinute(minute)
                        .withSecond(0)
                        .withNano(0)
                    selection.dateTime = selectedDateTime.takeIf { it.isAfter(ZonedDateTime.now()) }
                        ?: ZonedDateTime.now().plusMinutes(1).withSecond(0).withNano(0)
                    target.text = selection.displayText(this)
                },
                current.hour,
                current.minute,
                true,
            ).show()
        },
        current.year,
        current.monthValue - 1,
        current.dayOfMonth,
    ).apply {
        datePicker.minDate = System.currentTimeMillis()
    }.show()
}

internal fun TopicDetailActivity.scheduleBookmarkReminderAfterSave(request: BookmarkReminderRequest) {
    if (request.reminderAt.isNullOrBlank()) {
        BookmarkReminderScheduler.sync(this, request)
        return
    }
    if (
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
        ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
    ) {
        pendingNotificationPermissionRequest = request
        notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        return
    }
    BookmarkReminderScheduler.sync(this, request)
}

internal fun TopicDetailActivity.bookmarkReminderTitle(bookmarkableType: String, targetPostNumber: UInt?): String {
    val detail = viewModel?.detail?.value
    val title = detail?.title?.trim()?.takeIf { it.isNotEmpty() }
        ?: route?.title?.trim()?.takeIf { it.isNotEmpty() }
        ?: getString(R.string.topic_detail_title_fallback, route?.topicId?.toString().orEmpty())
    return if (bookmarkableType.equals("Post", ignoreCase = true) && targetPostNumber != null) {
        "$title #$targetPostNumber"
    } else {
        title
    }
}

internal data class BookmarkReminderKey(
    val bookmarkableId: ULong,
    val bookmarkableType: String,
)

internal class BookmarkReminderSelection(
    var hasReminder: Boolean,
    var dateTime: ZonedDateTime?,
) {
    fun reminderAt(): String? {
        if (!hasReminder) return null
        val normalizedDateTime = dateTime
            ?.takeIf { it.isAfter(ZonedDateTime.now()) }
            ?: ZonedDateTime.now().plusMinutes(1)
        return normalizedDateTime
            ?.withSecond(0)
            ?.withNano(0)
            ?.toInstant()
            ?.toString()
    }

    fun displayText(context: Context): String {
        val dateTime = dateTime ?: return context.getString(R.string.topic_detail_bookmark_reminder_pick)
        return DateTimeFormatter
            .ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
            .format(dateTime.withZoneSameInstant(ZoneId.systemDefault()))
    }

    companion object {
        fun from(rawValue: String?): BookmarkReminderSelection {
            val parsed = rawValue
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
                ?.let { runCatching { Instant.parse(it).atZone(ZoneId.systemDefault()) }.getOrNull() }
            return BookmarkReminderSelection(
                hasReminder = parsed != null,
                dateTime = parsed,
            )
        }
    }
}
