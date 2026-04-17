package com.fire.app

import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import uniffi.fire_uniffi_session.TopicCategoryState
import uniffi.fire_uniffi_types.TopicTagState

fun TopicCategoryState.displayName(): String {
    return if (name.isBlank()) "Category #$id" else name
}

object TopicPresentation {
    private val displayFormatter: DateTimeFormatter =
        DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
            .withLocale(Locale.getDefault())
    private val displayZoneId: ZoneId = ZoneId.systemDefault()

    fun formatTimestamp(rawValue: String?): String? {
        if (rawValue.isNullOrBlank()) {
            return null
        }

        return runCatching {
            displayFormatter.format(OffsetDateTime.parse(rawValue))
        }.getOrElse { rawValue }
    }

    fun formatTimestamp(unixMs: ULong?): String? {
        if (unixMs == null) {
            return null
        }

        return runCatching {
            displayFormatter.format(Instant.ofEpochMilli(unixMs.toLong()).atZone(displayZoneId))
        }.getOrNull()
    }

    fun tagNames(tags: List<TopicTagState>): List<String> {
        return tags.mapNotNull { tag ->
            tag.name.takeIf { it.isNotBlank() } ?: tag.slug?.takeIf { it.isNotBlank() }
        }
    }
}
