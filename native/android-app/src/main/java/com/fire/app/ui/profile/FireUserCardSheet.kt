package com.fire.app.ui.profile

import android.app.Activity
import android.util.TypedValue
import android.view.Gravity
import android.widget.ImageView
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
import com.google.android.material.button.MaterialButton
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_chat.CreateDirectMessageChannelRequestState
import uniffi.fire_uniffi_user.UserProfileState

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
            layoutParams = LinearLayout.LayoutParams(activity.dp(52), activity.dp(52))
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
            setPadding(0, activity.dp(10), 0, 0)
            setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Caption)
        })
        val actions = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(0, activity.dp(12), 0, 0)
        }
        addAction(activity, actions, "主页", filled = false) {
            dialog.dismiss()
            com.fire.app.ui.webview.FireInAppWebViewActivity.start(
                activity,
                "https://linux.do/u/${profile.username}",
            )
        }
        if (!isOwnProfile) {
            if (profile.canSendPrivateMessageToUser) {
                addAction(
                    activity,
                    actions,
                    "私信",
                    filled = false,
                ) {
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
            addAction(activity, actions, "聊天", filled = true) {
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
        content.addView(actions)
    }

    private fun addAction(
        activity: Activity,
        row: LinearLayout,
        title: String,
        filled: Boolean,
        onClick: () -> Unit,
    ) {
        val style = if (filled) {
            com.google.android.material.R.attr.materialButtonStyle
        } else {
            com.google.android.material.R.attr.materialButtonOutlinedStyle
        }
        row.addView(
            MaterialButton(activity, null, style).apply {
                text = title
                isAllCaps = false
                insetTop = 0
                insetBottom = 0
                minHeight = activity.dp(34)
                minimumHeight = activity.dp(34)
                cornerRadius = activity.dp(10)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                    marginStart = activity.dp(4)
                    marginEnd = activity.dp(4)
                }
                setOnClickListener { onClick() }
            },
        )
    }
}
