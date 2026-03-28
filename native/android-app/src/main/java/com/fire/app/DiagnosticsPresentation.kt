package com.fire.app

import java.net.URI
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import uniffi.fire_uniffi.NetworkTraceHeaderState

object DiagnosticsPresentation {
    private val timestampFormatter: DateTimeFormatter =
        DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.MEDIUM)
            .withLocale(Locale.getDefault())
            .withZone(ZoneId.systemDefault())

    fun formatTimestamp(unixMs: ULong): String {
        return runCatching {
            timestampFormatter.format(Instant.ofEpochMilli(unixMs.toLong()))
        }.getOrElse {
            unixMs.toString()
        }
    }

    fun formatBytes(bytes: ULong): String {
        val value = bytes.toLong()
        if (value < 1024L) {
            return "$value B"
        }
        if (value < 1024L * 1024L) {
            return String.format(Locale.US, "%.1f KB", value / 1024.0)
        }
        return String.format(Locale.US, "%.1f MB", value / 1024.0 / 1024.0)
    }

    fun compactUrl(rawValue: String): String {
        return runCatching {
            val uri = URI(rawValue)
            buildString {
                append(uri.path?.takeIf { it.isNotBlank() } ?: "/")
                uri.query?.takeIf { it.isNotBlank() }?.let { query ->
                    append('?')
                    append(query)
                }
            }
        }.getOrElse { rawValue }
    }

    fun renderHeaders(headers: List<NetworkTraceHeaderState>): String {
        if (headers.isEmpty()) {
            return "No headers captured."
        }

        return headers.joinToString(separator = "\n") { header ->
            "${header.name}: ${header.value}"
        }
    }
}
