package com.fire.app.richtext.span

import android.text.TextPaint
import android.text.style.ClickableSpan
import android.view.View

class FireLinkSpan(
    private val url: String,
    private val onLinkClicked: ((String) -> Unit)? = null,
) : ClickableSpan() {

    override fun onClick(widget: View) {
        onLinkClicked?.invoke(url) ?: run {
            val intent = android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(url))
            widget.context.startActivity(intent)
        }
    }

    override fun updateDrawState(ds: TextPaint) {
        super.updateDrawState(ds)
        ds.isUnderlineText = false
    }
}
