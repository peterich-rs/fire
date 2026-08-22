package com.fire.app.ui.profile

import android.app.Activity
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.lifecycleScope
import com.fire.app.R
import com.fire.app.core.ext.dp
import com.fire.app.core.image.FireAvatarUrls
import com.fire.app.core.image.FireImageLoader
import com.fire.app.session.FireSessionStore
import com.fire.app.ui.chat.ChatChannelActivity
import com.fire.app.ui.composer.PrivateMessageComposerSheet
import com.fire.app.ui.topicdetail.TopicDetailActivity
import com.google.android.material.bottomsheet.BottomSheetDialog
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_chat.CreateDirectMessageChannelRequestState
import uniffi.fire_uniffi_user.UserProfileState
import android.widget.ImageView

object FireUserCardSheet {
    fun show(activity: FragmentActivity, sessionStore: FireSessionStore, username: String) {
        val normalized = username.trim().removePrefix("@").takeIf { it.isNotEmpty() } ?: return
        val dialog = BottomSheetDialog(activity)
        val content = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(activity.dp(20), activity.dp(18), activity.dp(20), activity.dp(24))
        }
        val loading = TextView(activity).apply {
            text = activity.getString(R.string.profile_loading)
        }
        content.addView(loading)
        dialog.setContentView(ScrollView(activity).apply { addView(content) })
        dialog.show()

        activity.lifecycleScope.launch {
            try {
                val profile = sessionStore.fetchUserProfile(normalized)
                val summary = runCatching { sessionStore.fetchUserSummary(normalized) }.getOrNull()
                val currentUsername = runCatching {
                    sessionStore.snapshot().bootstrap.currentUsername
                }.getOrNull()?.trim()
                if (!dialog.isShowing) return@launch
                render(
                    activity = activity,
                    sessionStore = sessionStore,
                    content = content,
                    dialog = dialog,
                    profile = profile,
                    statsLine = buildList {
                        add(activity.getString(R.string.profile_topics_count, (summary?.stats?.topicCount ?: 0u).toString()))
                        add(activity.getString(R.string.profile_posts_count, (summary?.stats?.postCount ?: 0u).toString()))
                        add(activity.getString(R.string.profile_likes_received, (summary?.stats?.likesReceived ?: 0u).toString()))
                    }.joinToString(" · "),
                    isOwnProfile = currentUsername.equals(profile.username.trim(), ignoreCase = true),
                )
            } catch (error: Exception) {
                if (!dialog.isShowing) return@launch
                content.removeAllViews()
                content.addView(TextView(activity).apply {
                    text = error.localizedMessage ?: activity.getString(R.string.profile_error)
                })
            }
        }
    }

    private fun render(
        activity: FragmentActivity,
        sessionStore: FireSessionStore,
        content: LinearLayout,
        dialog: BottomSheetDialog,
        profile: UserProfileState,
        statsLine: String,
        isOwnProfile: Boolean,
    ) {
        content.removeAllViews()
        val header = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val avatar = ImageView(activity).apply {
            layoutParams = LinearLayout.LayoutParams(activity.dp(64), activity.dp(64))
            scaleType = ImageView.ScaleType.CENTER_CROP
        }
        profile.avatarTemplate?.let { template ->
            FireAvatarUrls.build(template)?.let { FireImageLoader.load(it, avatar) }
        }
        val titles = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(activity.dp(14), 0, 0, 0)
        }
        titles.addView(TextView(activity).apply {
            text = profile.name?.takeIf { it.isNotBlank() } ?: profile.username
            setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Title)
        })
        titles.addView(TextView(activity).apply {
            text = "@${profile.username} · ${profile.trustLevelLabel}"
            setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Caption)
        })
        header.addView(avatar)
        header.addView(titles)
        content.addView(header)
        content.addView(TextView(activity).apply {
            text = statsLine
            setPadding(0, activity.dp(12), 0, 0)
        })
        addAction(activity, content, "查看主页") {
            dialog.dismiss()
            com.fire.app.ui.webview.FireInAppWebViewActivity.start(
                activity,
                "https://linux.do/u/${profile.username}",
            )
        }
        if (!isOwnProfile) {
            if (profile.canSendPrivateMessageToUser) {
                addAction(activity, content, activity.getString(R.string.profile_send_private_message)) {
                    dialog.dismiss()
                    PrivateMessageComposerSheet.newInstance(
                        targetUsername = profile.username,
                        displayName = profile.name?.takeIf { it.isNotBlank() } ?: profile.username,
                        onPrivateMessageCreated = { topicId, title ->
                            TopicDetailActivity.start(
                                context = activity,
                                topicId = topicId.toLong(),
                                topicTitle = title,
                            )
                        },
                    ).show(activity.supportFragmentManager, "private_message_composer")
                }
            }
            addAction(activity, content, "聊天") {
                dialog.dismiss()
                activity.lifecycleScope.launch {
                    val channel = sessionStore.createDirectMessageChannel(
                        CreateDirectMessageChannelRequestState(
                            targetUsernames = listOf(profile.username),
                            name = null,
                            upsert = true,
                        ),
                    )
                    activity.startActivity(
                        ChatChannelActivity.intent(
                            activity,
                            channelId = channel.id,
                            title = channel.displayTitle,
                        ),
                    )
                }
            }
        }
    }

    private fun addAction(
        activity: Activity,
        content: LinearLayout,
        title: String,
        onClick: () -> Unit,
    ) {
        content.addView(TextView(activity).apply {
            text = title
            gravity = Gravity.CENTER
            setPadding(activity.dp(12), activity.dp(10), activity.dp(12), activity.dp(10))
            setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Button)
            setTextColor(activity.getColor(R.color.fire_accent))
            setOnClickListener { onClick() }
        })
    }
}
