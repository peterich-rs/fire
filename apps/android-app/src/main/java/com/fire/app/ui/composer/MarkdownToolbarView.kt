package com.fire.app.ui.composer

import android.content.Context
import android.graphics.Typeface
import android.util.AttributeSet
import android.util.TypedValue
import android.view.Gravity
import android.widget.EditText
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.TextView
import com.fire.app.R
import com.fire.app.core.ext.dp

class MarkdownToolbarView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : HorizontalScrollView(context, attrs, defStyleAttr) {

    private val buttonRow = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(context.dp(4), context.dp(4), context.dp(4), context.dp(4))
    }
    private var targetInput: EditText? = null

    init {
        isHorizontalScrollBarEnabled = false
        overScrollMode = OVER_SCROLL_NEVER
        setBackgroundColor(context.getColor(R.color.fire_background_canvas))
        addView(
            buttonRow,
            LayoutParams(
                LayoutParams.WRAP_CONTENT,
                LayoutParams.WRAP_CONTENT,
            ),
        )
        MarkdownToolbarItem.entries.forEach { item ->
            buttonRow.addView(toolbarButton(item))
        }
    }

    fun bind(input: EditText) {
        targetInput = input
    }

    private fun toolbarButton(item: MarkdownToolbarItem): TextView {
        val background = TypedValue()
        context.theme.resolveAttribute(android.R.attr.selectableItemBackgroundBorderless, background, true)
        return TextView(context).apply {
            text = item.label
            contentDescription = context.getString(item.contentDescriptionRes)
            gravity = Gravity.CENTER
            minWidth = context.dp(36)
            minHeight = context.dp(34)
            setPadding(context.dp(8), 0, context.dp(8), 0)
            setTextColor(context.getColor(R.color.fire_text_primary))
            textSize = 14f
            typeface = when (item.action) {
                MarkdownFormatAction.BOLD -> Typeface.DEFAULT_BOLD
                MarkdownFormatAction.ITALIC -> Typeface.create(Typeface.DEFAULT, Typeface.ITALIC)
                else -> Typeface.DEFAULT
            }
            paint.isStrikeThruText = item.action == MarkdownFormatAction.STRIKETHROUGH
            setBackgroundResource(background.resourceId)
            setOnClickListener {
                targetInput?.let { input -> applyMarkdownFormat(input, item.action) }
            }
        }
    }
}

private enum class MarkdownToolbarItem(
    val action: MarkdownFormatAction,
    val label: String,
    val contentDescriptionRes: Int,
) {
    BOLD(MarkdownFormatAction.BOLD, "B", R.string.composer_markdown_bold),
    ITALIC(MarkdownFormatAction.ITALIC, "I", R.string.composer_markdown_italic),
    STRIKETHROUGH(MarkdownFormatAction.STRIKETHROUGH, "S", R.string.composer_markdown_strikethrough),
    INLINE_CODE(MarkdownFormatAction.INLINE_CODE, "<>", R.string.composer_markdown_inline_code),
    CODE_BLOCK(MarkdownFormatAction.CODE_BLOCK, "```", R.string.composer_markdown_code_block),
    QUOTE(MarkdownFormatAction.QUOTE, ">", R.string.composer_markdown_quote),
    UNORDERED_LIST(MarkdownFormatAction.UNORDERED_LIST, "- ", R.string.composer_markdown_unordered_list),
    ORDERED_LIST(MarkdownFormatAction.ORDERED_LIST, "1.", R.string.composer_markdown_ordered_list),
    LINK(MarkdownFormatAction.LINK, "[]", R.string.composer_markdown_link),
    IMAGE(MarkdownFormatAction.IMAGE, "![]", R.string.composer_markdown_image),
}
