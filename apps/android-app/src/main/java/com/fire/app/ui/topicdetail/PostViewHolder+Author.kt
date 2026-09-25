package com.fire.app.ui.topicdetail

import android.graphics.drawable.GradientDrawable
import android.text.TextUtils
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import com.fire.app.R
import uniffi.fire_uniffi_topics.TopicPostState

internal data class AuthorMetadataChip(
    val label: String,
    val textColorRes: Int,
    val backgroundColorRes: Int,
)

internal fun PostViewHolder.bindAuthorChips(chips: List<AuthorMetadataChip>) {
    authorChips.removeAllViews()
    authorChips.visibility = if (chips.isEmpty()) View.GONE else View.VISIBLE
    val context = itemView.context
    chips.forEachIndexed { index, chip ->
        val chipView = TextView(context).apply {
            text = chip.label
            setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Caption)
            setTextColor(context.getColor(chip.textColorRes))
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            includeFontPadding = false
            setPadding(dp(6), dp(2), dp(6), dp(2))
            background = GradientDrawable().apply {
                cornerRadius = dp(9).toFloat()
                setColor(context.getColor(chip.backgroundColorRes))
            }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                if (index > 0) marginStart = dp(4)
            }
        }
        authorChips.addView(chipView)
    }
}

internal fun displayName(post: TopicPostState): String {
    return cleaned(post.name)
        ?: cleaned(post.username)
        ?: "Unknown"
}

internal fun primaryMetadataParts(post: TopicPostState): List<AuthorMetadataChip> {
    val metadata = post.authorMetadata
    // Fluxdo-style: staff roles only on the primary line.
    // Trust title sits on the secondary @username line; flair/group are not text chips.
    return buildList {
        if (metadata.admin) {
            add(AuthorMetadataChip("管理员", R.color.fire_error, R.color.fire_chip_error_background))
        }
        if (metadata.moderator) {
            add(AuthorMetadataChip("版主", R.color.fire_link, R.color.fire_chip_link_background))
        }
        if (metadata.groupModerator) {
            add(AuthorMetadataChip("组版主", R.color.fire_warning, R.color.fire_chip_warning_background))
        }
    }.take(MAX_PRIMARY_METADATA_CHIPS)
}

internal fun secondaryMetadataParts(post: TopicPostState): List<String> {
    val metadata = post.authorMetadata
    val username = cleaned(post.username)
    val title = cleaned(metadata.userTitle)?.let(::humanizedUserTitle)
    val statusDescription = cleaned(metadata.userStatusDescription)
    val statusEmoji = cleaned(metadata.userStatusEmoji)?.let { ":$it:" }

    return buildList {
        username?.let { add("@$it") }
        title?.let { add(compactSecondaryLabel(it)) }
        if (statusDescription != null) {
            add(compactSecondaryLabel(statusDescription))
        } else {
            statusEmoji?.let(::add)
        }
    }
}

internal fun cleaned(value: String?): String? {
    return value?.trim()?.takeIf { it.isNotEmpty() }
}

private fun humanizedUserTitle(title: String): String {
    val level = parsedTrustLevel(title) ?: return title
    return trustLevelDisplayLabel(level)
}

private fun parsedTrustLevel(value: String): Int? {
    for (regex in TRUST_LEVEL_REGEXES) {
        val match = regex.find(value) ?: continue
        val level = match.groupValues.getOrNull(1)?.toIntOrNull() ?: continue
        return level
    }
    return null
}

private fun trustLevelDisplayLabel(level: Int): String {
    return when (level) {
        0 -> "L0 新用户"
        1 -> "L1 基本用户"
        2 -> "L2 成员"
        3 -> "L3 活跃用户"
        4 -> "L4 领袖"
        else -> "L$level"
    }
}

private fun compactSecondaryLabel(value: String): String {
    return if (value.length <= MAX_SECONDARY_LABEL_LENGTH) {
        value
    } else {
        value.take(MAX_SECONDARY_LABEL_LENGTH - 1) + "…"
    }
}

private const val MAX_PRIMARY_METADATA_CHIPS = 3
private const val MAX_SECONDARY_LABEL_LENGTH = 16
private val TRUST_LEVEL_REGEXES = listOf(
    Regex("""(?i)trust[_\s-]*l(?:evel|v)[_\s-]*(\d+)"""),
    Regex("""(?i)\btl[_\s-]*(\d+)\b"""),
    Regex("""(?i)\blv\.?\s*(\d+)\b"""),
    Regex("""(?i)\bl(\d+)\b"""),
    Regex("""等级\s*(\d+)"""),
    Regex("""(?i)level\s*(\d+)"""),
)
