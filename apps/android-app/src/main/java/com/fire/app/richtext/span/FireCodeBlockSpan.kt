package com.fire.app.richtext.span

import android.graphics.Canvas
import android.graphics.Paint
import android.text.style.ReplacementSpan

class FireCodeBlockSpan(
    private val backgroundColor: Int,
    private val cornerRadius: Float = 8f,
    private val horizontalPadding: Int = 12,
    private val verticalPadding: Int = 8,
) : ReplacementSpan() {

    override fun getSize(
        paint: Paint,
        text: CharSequence,
        start: Int,
        end: Int,
        fm: Paint.FontMetricsInt?,
    ): Int {
        val textWidth = paint.measureText(text, start, end).toInt()
        if (fm != null) {
            val lineHeight = paint.fontMetricsInt
            fm.ascent = lineHeight.ascent - verticalPadding
            fm.descent = lineHeight.descent + verticalPadding
            fm.top = fm.ascent
            fm.bottom = fm.descent
        }
        return textWidth + horizontalPadding * 2
    }

    override fun draw(
        canvas: Canvas,
        text: CharSequence,
        start: Int,
        end: Int,
        x: Float,
        top: Int,
        baseline: Int,
        bottom: Int,
        paint: Paint,
    ) {
        val width = getSize(paint, text, start, end, null).toFloat()
        val height = (bottom - top).toFloat()

        val rect = android.graphics.RectF(x, top.toFloat(), x + width, top + height)
        val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = backgroundColor; style = Paint.Style.FILL }
        canvas.drawRoundRect(rect, cornerRadius, cornerRadius, bgPaint)

        canvas.drawText(text, start, end, x + horizontalPadding, baseline.toFloat(), paint)
    }
}
