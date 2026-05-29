package com.fire.app.richtext.span

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.text.Layout
import android.text.Spanned
import android.text.style.QuoteSpan

class FireQuoteSpan(
    private val stripeColor: Int,
    private val stripeWidth: Int,
    private val backgroundColor: Int,
) : QuoteSpan() {

    override fun getLeadingMargin(first: Boolean): Int = stripeWidth + 8

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
        c.drawRect(x.toFloat(), top.toFloat(), (x + stripeWidth + 4).toFloat(), bottom.toFloat(), p)

        p.style = Paint.Style.FILL
        p.color = stripeColor
        c.drawRect(x.toFloat(), top.toFloat(), (x + stripeWidth).toFloat(), bottom.toFloat(), p)

        p.style = style
        p.color = color
    }
}
