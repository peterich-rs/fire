package com.fire.app.richtext.span

import android.text.style.ClickableSpan
import android.view.View

class FireSpoilerSpan(
    private val onReveal: (() -> Unit)? = null,
) : ClickableSpan() {

    var isRevealed: Boolean = false

    override fun onClick(widget: View) {
        isRevealed = !isRevealed
        onReveal?.invoke()
        widget.invalidate()
    }

    override fun updateDrawState(ds: android.text.TextPaint) {
        // Don't call super — we control our own appearance
        if (isRevealed) {
            ds.isStrikeThruText = false
            ds.bgColor = 0
        } else {
            ds.isStrikeThruText = true
            ds.bgColor = 0x339CA3AF.toInt()
        }
    }
}
