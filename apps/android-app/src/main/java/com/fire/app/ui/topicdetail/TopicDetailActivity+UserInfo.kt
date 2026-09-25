package com.fire.app.ui.topicdetail

import android.view.Gravity
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.lifecycle.lifecycleScope
import com.fire.app.R
import com.fire.app.core.ext.dp
import com.fire.app.core.image.FireAvatarUrls
import com.fire.app.core.image.FireImageLoader
import com.fire.app.session.FireSessionStoreRepository
import com.fire.app.ui.composer.PrivateMessageComposerSheet
import com.fire.app.ui.profile.FireUserCardSheet
import com.google.android.material.bottomsheet.BottomSheetDialog
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_user.UserProfileState
import uniffi.fire_uniffi_user.UserSummaryState

internal fun TopicDetailActivity.showUserInfoSheet(username: String) {
    lifecycleScope.launch {
        FireUserCardSheet.show(
            this@showUserInfoSheet,
            FireSessionStoreRepository.get(this@showUserInfoSheet),
            username,
        )
    }
}

internal fun TopicDetailActivity.showUserInfoSheetLegacy(username: String) {
    val normalized = username.trim().removePrefix("@").takeIf { it.isNotEmpty() } ?: return
    val dialog = BottomSheetDialog(this)
    val content = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(20), dp(18), dp(20), dp(24))
    }
    val loading = TextView(this).apply {
        text = getString(R.string.profile_loading)
        setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Body1)
        setTextColor(getColor(R.color.fire_text_secondary))
    }
    content.addView(loading)
    dialog.setContentView(ScrollView(this).apply { addView(content) })
    dialog.show()

    lifecycleScope.launch {
        try {
            val profile = sessionStore.fetchUserProfile(normalized)
            val summary = runCatching { sessionStore.fetchUserSummary(normalized) }.getOrNull()
            val currentUsername = runCatching {
                sessionStore.snapshot().bootstrap.currentUsername
            }.getOrNull()?.trim()
            if (!dialog.isShowing) return@launch
            renderUserInfoSheet(
                content = content,
                dialog = dialog,
                profile = profile,
                summary = summary,
                isOwnProfile = currentUsername.equals(profile.username.trim(), ignoreCase = true),
            )
        } catch (e: Exception) {
            if (!dialog.isShowing) return@launch
            content.removeAllViews()
            content.addView(TextView(this@showUserInfoSheetLegacy).apply {
                text = e.localizedMessage ?: getString(R.string.profile_error)
                setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Body1)
                setTextColor(getColor(R.color.fire_text_secondary))
            })
        }
    }
}

internal fun TopicDetailActivity.renderUserInfoSheet(
    content: LinearLayout,
    dialog: BottomSheetDialog,
    profile: UserProfileState,
    summary: UserSummaryState?,
    isOwnProfile: Boolean,
) {
    content.removeAllViews()
    val header = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
    }
    val avatar = ImageView(this).apply {
        layoutParams = LinearLayout.LayoutParams(dp(64), dp(64))
        scaleType = ImageView.ScaleType.CENTER_CROP
        contentDescription = getString(R.string.content_desc_avatar)
    }
    profile.avatarTemplate?.takeIf { it.isNotBlank() }?.let { template ->
        FireAvatarUrls.build(template)?.let { url ->
            FireImageLoader.load(url, avatar)
        }
    }
    val titleStack = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(14), 0, 0, 0)
    }
    titleStack.addView(TextView(this).apply {
        text = profile.name?.takeIf { it.isNotBlank() } ?: profile.username
        setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Title)
        setTextColor(getColor(R.color.fire_text_primary))
    })
    titleStack.addView(TextView(this).apply {
        text = "@${profile.username} · ${profile.trustLevelLabel}"
        setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Caption)
        setTextColor(getColor(R.color.fire_text_secondary))
    })
    header.addView(avatar)
    header.addView(titleStack)
    content.addView(header)

    val stats = summary?.stats
    val statText = buildList {
        add(getString(R.string.profile_topics_count, (stats?.topicCount ?: 0u).toString()))
        add(getString(R.string.profile_posts_count, (stats?.postCount ?: 0u).toString()))
        add(getString(R.string.profile_likes_received, (stats?.likesReceived ?: 0u).toString()))
        add(getString(R.string.profile_followers_count, profile.totalFollowers.toString()))
    }.joinToString("\n")
    content.addView(TextView(this).apply {
        text = statText
        setPadding(0, dp(16), 0, 0)
        setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Body1)
        setTextColor(getColor(R.color.fire_text_primary))
    })

    profile.bioPlainText?.trim()?.takeIf { it.isNotEmpty() }?.let { bio ->
        content.addView(TextView(this).apply {
            text = bio
            setPadding(0, dp(14), 0, 0)
            setTextIsSelectable(true)
            setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Body2)
            setTextColor(getColor(R.color.fire_text_secondary))
        })
    }

    if (!isOwnProfile && profile.canSendPrivateMessageToUser) {
        content.addView(TextView(this).apply {
            text = getString(R.string.profile_send_private_message)
            gravity = Gravity.CENTER
            setPadding(dp(12), dp(10), dp(12), dp(10))
            setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Button)
            setTextColor(getColor(R.color.fire_accent))
            setOnClickListener {
                dialog.dismiss()
                PrivateMessageComposerSheet.newInstance(
                    targetUsername = profile.username,
                    displayName = profile.name?.takeIf { it.isNotBlank() } ?: profile.username,
                    onPrivateMessageCreated = { topicId, title ->
                        TopicDetailActivity.start(
                            context = this@renderUserInfoSheet,
                            topicId = topicId.toLong(),
                            topicTitle = title,
                        )
                    },
                ).show(supportFragmentManager, "private_message_composer")
            }
        })
    }
}
