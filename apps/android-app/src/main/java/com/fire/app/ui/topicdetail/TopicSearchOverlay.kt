package com.fire.app.ui.topicdetail

import android.content.Context
import android.util.AttributeSet
import android.view.Gravity
import android.view.inputmethod.InputMethodManager
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.widget.doAfterTextChanged
import com.fire.app.R
import com.fire.app.core.ext.dp
import com.google.android.material.textfield.TextInputEditText
import com.google.android.material.textfield.TextInputLayout

class TopicSearchOverlay @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : LinearLayout(context, attrs) {
    private val searchInput: TextInputEditText
    private val resultText: TextView
    private var onQueryChanged: ((String) -> Unit)? = null
    private var onPrevious: (() -> Unit)? = null
    private var onNext: (() -> Unit)? = null
    private var onClose: (() -> Unit)? = null
    private var suppressQueryCallback = false

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(context.dp(12), context.dp(8), context.dp(8), context.dp(8))
        setBackgroundColor(context.getColor(R.color.fire_background_surface))
        elevation = context.dp(4).toFloat()

        val inputLayout = TextInputLayout(context).apply {
            hint = context.getString(R.string.topic_detail_search_hint)
            layoutParams = LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f)
        }
        searchInput = TextInputEditText(context).apply {
            isSingleLine = true
            setTextColor(context.getColor(R.color.fire_text_primary))
            setOnEditorActionListener { _, _, _ ->
                onNext?.invoke()
                true
            }
            doAfterTextChanged { text ->
                if (!suppressQueryCallback) {
                    onQueryChanged?.invoke(text?.toString().orEmpty())
                }
            }
        }
        inputLayout.addView(searchInput)

        resultText = TextView(context).apply {
            setTextColor(context.getColor(R.color.fire_text_secondary))
            textSize = 13f
            gravity = Gravity.CENTER
            layoutParams = LayoutParams(context.dp(58), LayoutParams.WRAP_CONTENT).apply {
                marginStart = context.dp(8)
            }
        }

        addView(inputLayout)
        addView(resultText)
        addView(iconButton(R.drawable.ic_chevron_up, R.string.topic_detail_search_previous) {
            onPrevious?.invoke()
        })
        addView(iconButton(R.drawable.ic_chevron_down, R.string.topic_detail_search_next) {
            onNext?.invoke()
        })
        addView(iconButton(R.drawable.ic_close, R.string.topic_detail_search_close) {
            onClose?.invoke()
        })

        updateResult(currentIndex = -1, total = 0)
    }

    fun bind(
        onQueryChanged: (String) -> Unit,
        onPrevious: () -> Unit,
        onNext: () -> Unit,
        onClose: () -> Unit,
    ) {
        this.onQueryChanged = onQueryChanged
        this.onPrevious = onPrevious
        this.onNext = onNext
        this.onClose = onClose
    }

    fun focusSearch() {
        searchInput.requestFocus()
        post {
            val manager = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            manager?.showSoftInput(searchInput, InputMethodManager.SHOW_IMPLICIT)
        }
    }

    fun reset() {
        suppressQueryCallback = true
        searchInput.setText("")
        suppressQueryCallback = false
        updateResult(currentIndex = -1, total = 0)
    }

    fun updateResult(currentIndex: Int, total: Int) {
        resultText.text = if (total > 0 && currentIndex >= 0) {
            context.getString(R.string.topic_detail_search_count, (currentIndex + 1).toString(), total.toString())
        } else {
            context.getString(R.string.topic_detail_search_no_results)
        }
    }

    private fun iconButton(iconRes: Int, contentDescriptionRes: Int, onClick: () -> Unit): ImageButton {
        return ImageButton(context).apply {
            setImageResource(iconRes)
            contentDescription = context.getString(contentDescriptionRes)
            background = null
            setColorFilter(context.getColor(R.color.fire_text_primary))
            setPadding(context.dp(8), context.dp(8), context.dp(8), context.dp(8))
            layoutParams = LayoutParams(context.dp(40), context.dp(40))
            setOnClickListener { onClick() }
        }
    }
}
