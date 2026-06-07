package com.fire.app.richtext.span

import android.graphics.Canvas
import android.graphics.Paint
import android.text.Layout
import android.text.Spanned
import android.text.style.QuoteSpan

class FireQuoteSpan(
    private val insetWidth: Int,
    private val backgroundColor: Int,
) : QuoteSpan() {

    override fun getLeadingMargin(first: Boolean): Int = insetWidth

    override fun drawLeadingMargin(
        c: Canvas,
        p: Paint,
        x: Int,
        dir: Int,
        top: Int,
        baseline: Int,
        bottom: Int,
        text: CharSequence,
        start: Int,
        end: Int,
        first: Boolean,
        layout: Layout,
    ) {
        val style = p.style
        val color = p.color

        p.style = Paint.Style.FILL
        p.color = backgroundColor
        val left = if (dir >= 0) x.toFloat() else (x - c.width).toFloat()
        val right = if (dir >= 0) c.width.toFloat() else x.toFloat()
        c.drawRect(left, top.toFloat(), right, bottom.toFloat(), p)

        p.style = style
        p.color = color
    }
}
