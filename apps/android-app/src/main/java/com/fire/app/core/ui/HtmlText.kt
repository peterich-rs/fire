package com.fire.app.core.ui

import androidx.core.text.HtmlCompat

object HtmlText {
    fun toPlain(html: String?): String? {
        val raw = html?.trim().orEmpty()
        if (raw.isEmpty()) return null
        return HtmlCompat.fromHtml(raw, HtmlCompat.FROM_HTML_MODE_COMPACT)
            .toString()
            .trim()
            .ifEmpty { null }
    }
}
