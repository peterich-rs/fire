package com.fire.app.richtext.span

import android.graphics.Canvas
import android.graphics.Paint
import android.text.Layout
import android.text.Spanned
import android.text.style.QuoteSpan

class FireQuoteSpan(
    private val insetWidth: Int,
    private val backgroundColor: Int,
    private val stripeColor: Int,
) : QuoteSpan() {

    private val stripeWidth: Int = maxOf(3, insetWidth / 4)
    private val stripeGap: Int = maxOf(6, insetWidth / 2)

    override fun getLeadingMargin(first: Boolean): Int = insetWidth + stripeWidth + stripeGap

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

        p.color = stripeColor
        val stripeLeft = if (dir >= 0) {
            x + insetWidth / 2
        } else {
            x - insetWidth / 2 - stripeWidth
        }.toFloat()
        c.drawRoundRect(
            stripeLeft,
            top.toFloat(),
            stripeLeft + stripeWidth,
            bottom.toFloat(),
            stripeWidth / 2f,
            stripeWidth / 2f,
            p,
        )

        p.style = style
        p.color = color
    }
}
