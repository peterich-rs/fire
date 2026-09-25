package com.fire.app.ui.composer

import android.content.Context
import android.widget.TextView
import com.fire.app.R

internal fun suggestionView(context: Context, label: String, onClick: () -> Unit): TextView {
    return TextView(context).apply {
        text = label
        setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Caption)
        setTextColor(context.getColor(R.color.fire_accent))
        setPadding(0, 8, 0, 8)
        setOnClickListener { onClick() }
    }
}

internal data class Suggestion(val label: String, val value: String)

internal data class TextContext(val start: Int, val end: Int, val term: String)
