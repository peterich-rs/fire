package com.fire.app.richtext

import android.content.Context
import android.graphics.drawable.Drawable
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.util.AttributeSet
import android.util.LruCache
import androidx.appcompat.widget.AppCompatTextView
import coil.request.ImageRequest
import com.fire.app.core.image.FireImageLoader

class FireRichTextView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = android.R.attr.textViewStyle,
) : AppCompatTextView(context, attrs, defStyleAttr) {

    var renderedContentId: String? = null
        private set

    private var emojiLoadJobs = mutableMapOf<String, Drawable?>()
    private var measuredWidth: Int = 0
    private var cachedIntrinsicHeight: Int? = null

    init {
        isClickable = true
        isFocusable = false
        includeFontPadding = true
        movementMethod = android.text.method.LinkMovementMethod.getInstance()
        setLineSpacing(4f, 1.12f)
    }

    fun setContent(contentId: String, spannable: Spanned) {
        if (renderedContentId == contentId) return
        renderedContentId = contentId
        setText(spannable)
        loadEmojiSpans()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        if (width > 0 && (measuredWidth == 0 || abs(width - measuredWidth) > 0)) {
            measuredWidth = width
            cachedIntrinsicHeight = null
        }
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        val width = right - left - paddingStart - paddingEnd
        if (width > 0 && abs(width - measuredWidth) > 0) {
            measuredWidth = width
            cachedIntrinsicHeight = null
            requestLayout()
        }
    }

    private fun loadEmojiSpans() {
        val text = text as? Spanned ?: return
        val placeholders = text.getSpans(0, text.length, FireSpannableBuilder.FireEmojiPlaceholderSpan::class.java)
        for (placeholder in placeholders) {
            val url = placeholder.url
            if (emojiLoadJobs.containsKey(url)) continue
            emojiLoadJobs[url] = null

            val request = ImageRequest.Builder(context)
                .data(url)
                .allowHardware(false)
                .target { drawable ->
                    emojiLoadJobs[url] = drawable
                    applyEmojiDrawable(url, drawable, placeholder)
                }
                .build()
            FireImageLoader.loader().enqueue(request)
        }
    }

    private fun applyEmojiDrawable(url: String, drawable: Drawable, placeholder: FireSpannableBuilder.FireEmojiPlaceholderSpan) {
        val text = text as? Spanned ?: return
        val start = text.getSpanStart(placeholder)
        val end = text.getSpanEnd(placeholder)
        if (start < 0 || end < 0) return

        val size = if (placeholder.onlyEmoji) (textSize * 1.9f).toInt() else (textSize * 1.15f).toInt()
        drawable.setBounds(0, 0, size, size)

        val imageSpan = android.text.style.ImageSpan(drawable, url)
        text as SpannableStringBuilder? ?: return
        (text as SpannableStringBuilder).removeSpan(placeholder)
        (text as SpannableStringBuilder).setSpan(imageSpan, start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        invalidate()
    }

    private fun abs(value: Int): Int = if (value < 0) -value else value

    companion object {
        private val intrinsicHeightCache = LruCache<String, Int>(256)
    }
}
