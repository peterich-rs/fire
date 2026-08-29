package com.fire.app.ui.profile

import java.time.Instant
import java.time.OffsetDateTime
import java.util.concurrent.TimeUnit

object ProfileFormat {
    fun number(value: UInt): String = number(value.toLong())

    fun number(value: Long): String {
        return when {
            value >= 10_000 -> String.format("%.1fw", value / 10_000.0)
            value >= 1_000 -> String.format("%.1fK", value / 1_000.0)
            else -> value.toString()
        }
    }

    fun relativeTime(isoDate: String?): String? {
        val parsed = parseInstant(isoDate) ?: return isoDate
        val deltaMs = System.currentTimeMillis() - parsed.toEpochMilli()
        val minutes = TimeUnit.MILLISECONDS.toMinutes(deltaMs)
        val hours = TimeUnit.MILLISECONDS.toHours(deltaMs)
        val days = TimeUnit.MILLISECONDS.toDays(deltaMs)
        return when {
            minutes < 1 -> "刚刚"
            minutes < 60 -> "${minutes} 分钟前"
            hours < 24 -> "${hours} 小时前"
            days < 7 -> "${days} 天前"
            else -> isoDate
        }
    }

    private fun parseInstant(raw: String?): Instant? {
        val value = raw?.trim().orEmpty()
        if (value.isEmpty()) return null
        return runCatching { Instant.parse(value) }.getOrNull()
            ?: runCatching { OffsetDateTime.parse(value).toInstant() }.getOrNull()
            ?: runCatching {
                java.time.LocalDateTime.parse(value).atOffset(java.time.ZoneOffset.UTC).toInstant()
            }.getOrNull()
    }
}
