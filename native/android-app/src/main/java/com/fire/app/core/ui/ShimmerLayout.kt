package com.fire.app.core.ui

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import android.util.AttributeSet
import android.widget.FrameLayout
import com.fire.app.R
import kotlin.math.max

class ShimmerLayout @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : FrameLayout(context, attrs, defStyleAttr) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var shimmerOffset = 0f
    private var shimmerWidth = 0f
    private var animator: ValueAnimator? = null

    init {
        setWillNotDraw(false)
    }

    override fun onSizeChanged(width: Int, height: Int, oldWidth: Int, oldHeight: Int) {
        super.onSizeChanged(width, height, oldWidth, oldHeight)
        shimmerWidth = max(width * 0.45f, 1f)
        paint.shader = LinearGradient(
            -shimmerWidth,
            0f,
            shimmerWidth,
            0f,
            intArrayOf(
                context.getColor(R.color.fire_shimmer_edge),
                context.getColor(R.color.fire_shimmer_highlight),
                context.getColor(R.color.fire_shimmer_edge),
            ),
            floatArrayOf(0f, 0.5f, 1f),
            Shader.TileMode.CLAMP,
        )
        restartAnimatorIfNeeded()
    }

    override fun dispatchDraw(canvas: Canvas) {
        super.dispatchDraw(canvas)
        if (width <= 0 || height <= 0) {
            return
        }
        canvas.save()
        canvas.translate(shimmerOffset, 0f)
        canvas.drawRect(-shimmerWidth, 0f, shimmerWidth, height.toFloat(), paint)
        canvas.restore()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        restartAnimatorIfNeeded()
    }

    override fun onDetachedFromWindow() {
        animator?.cancel()
        animator = null
        super.onDetachedFromWindow()
    }

    private fun restartAnimatorIfNeeded() {
        if (!isAttachedToWindow || width <= 0 || !ValueAnimator.areAnimatorsEnabled()) {
            animator?.cancel()
            animator = null
            return
        }
        if (animator?.isStarted == true) {
            return
        }
        animator = ValueAnimator.ofFloat(-shimmerWidth, width + shimmerWidth).apply {
            duration = 1200L
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.RESTART
            addUpdateListener {
                shimmerOffset = it.animatedValue as Float
                invalidate()
            }
            start()
        }
    }
}
