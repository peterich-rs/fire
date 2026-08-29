package com.fire.app.ui.profile.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Feedback
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.PersonRemove
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.VpnKey
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.automirrored.filled.ViewList
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fire.app.core.theme.compose.FireShapes
import com.fire.app.core.theme.compose.fireExtended
import com.fire.app.core.ui.HtmlText
import com.fire.app.core.ui.compose.FireEmptyState
import com.fire.app.core.ui.compose.FireErrorBanner
import com.fire.app.core.ui.compose.FireListRowContent
import com.fire.app.core.ui.compose.FireRemoteAvatar
import com.fire.app.core.ui.compose.FireSecondaryScaffold
import com.fire.app.core.ui.compose.FireSettingsCard
import com.fire.app.core.ui.compose.FireSettingsCardRows
import com.fire.app.ui.profile.ProfileFormat
import uniffi.fire_uniffi_user.UserActionState
import uniffi.fire_uniffi_user.UserProfileState
import uniffi.fire_uniffi_user.UserSummaryState

data class ProfileUiState(
    val profile: UserProfileState? = null,
    val summary: UserSummaryState? = null,
    val actions: List<UserActionState> = emptyList(),
    val isOwnProfile: Boolean = true,
    val isLoading: Boolean = false,
    val actionsLoading: Boolean = false,
    val hasLoadedActionsOnce: Boolean = false,
    val error: String? = null,
)

@Composable
fun ProfileScreen(
    state: ProfileUiState,
    onRefresh: () -> Unit,
    onFollowClick: () -> Unit,
    onMessageClick: () -> Unit,
    onFollowingClick: () -> Unit,
    onFollowersClick: () -> Unit,
    onActivityClick: () -> Unit,
    onActivityItemClick: (UserActionState) -> Unit,
    onBookmarksClick: () -> Unit,
    onHistoryClick: () -> Unit,
    onDraftsClick: () -> Unit,
    onMessagesClick: () -> Unit,
    onBadgesClick: () -> Unit,
    onFeedbackClick: () -> Unit,
    onInvitesClick: () -> Unit,
    onLdcClick: () -> Unit,
    onCdkClick: () -> Unit,
    onSettingsClick: () -> Unit,
    onBack: (() -> Unit)?,
    onDismissError: () -> Unit,
) {
    val colors = MaterialTheme.fireExtended
    val title = if (state.isOwnProfile) {
        "我的"
    } else {
        state.profile?.username ?: "主页"
    }
    FireSecondaryScaffold(
        title = title,
        onBack = onBack,
        actions = {
            IconButton(onClick = onRefresh) {
                Icon(
                    imageVector = Icons.Filled.Refresh,
                    contentDescription = "刷新",
                    tint = MaterialTheme.fireExtended.accent,
                )
            }
        },
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(top = 4.dp, bottom = 24.dp),
        ) {
                state.error?.let { message ->
                    FireErrorBanner(message = message, onDismiss = onDismissError)
                    Spacer(Modifier.height(12.dp))
                }

                val profile = state.profile
                if (profile == null) {
                    if (state.isLoading) {
                        FireEmptyState(title = "正在加载", message = "正在获取资料…")
                    } else if (state.error == null) {
                        FireEmptyState(title = "无法加载资料", message = "下拉刷新后再试。")
                    }
                } else {
                    ProfileHeaderCard(profile = profile, summary = state.summary)
                    Spacer(Modifier.height(12.dp))

                    if (!state.isOwnProfile) {
                        val actionRows = buildList {
                            if (profile.canFollow) {
                                add(
                                    FireListRowContent(
                                        icon = if (profile.isFollowed) Icons.Filled.PersonRemove else Icons.Filled.PersonAdd,
                                        title = if (profile.isFollowed) "取消关注" else "关注",
                                        showsChevron = false,
                                        iconWellColor = colors.accent,
                                    ) to onFollowClick,
                                )
                            }
                            if (profile.canSendPrivateMessageToUser) {
                                add(
                                    FireListRowContent(
                                        icon = Icons.Filled.Email,
                                        title = "发送私信",
                                        showsChevron = false,
                                        iconWellColor = colors.accent,
                                    ) to onMessageClick,
                                )
                            }
                        }
                        if (actionRows.isNotEmpty()) {
                            FireSettingsCardRows(rows = actionRows)
                            Spacer(Modifier.height(12.dp))
                        }
                    }

                    FireSettingsCardRows(
                        rows = listOf(
                            FireListRowContent(
                                icon = Icons.Filled.Group,
                                title = if (state.isOwnProfile) "关注列表" else "关注",
                                value = ProfileFormat.number(profile.totalFollowing),
                                iconWellColor = Color(0xFF007AFF),
                            ) to onFollowingClick,
                            FireListRowContent(
                                icon = Icons.Filled.Groups,
                                title = if (state.isOwnProfile) "粉丝列表" else "粉丝",
                                value = ProfileFormat.number(profile.totalFollowers),
                                iconWellColor = Color(0xFF5856D6),
                            ) to onFollowersClick,
                        ),
                    )
                    Spacer(Modifier.height(12.dp))

                    if (state.isOwnProfile) {
                        OwnProfileMenus(
                            state = state,
                            onActivityClick = onActivityClick,
                            onBookmarksClick = onBookmarksClick,
                            onHistoryClick = onHistoryClick,
                            onDraftsClick = onDraftsClick,
                            onMessagesClick = onMessagesClick,
                            onBadgesClick = onBadgesClick,
                            onFeedbackClick = onFeedbackClick,
                            onInvitesClick = onInvitesClick,
                            onLdcClick = onLdcClick,
                            onCdkClick = onCdkClick,
                            onSettingsClick = onSettingsClick,
                        )
                    } else {
                        PublicActivitySection(
                            state = state,
                            onActivityClick = onActivityClick,
                            onActivityItemClick = onActivityItemClick,
                        )
                    }
                }
            }
        }
    }

@Composable
private fun OwnProfileMenus(
    state: ProfileUiState,
    onActivityClick: () -> Unit,
    onBookmarksClick: () -> Unit,
    onHistoryClick: () -> Unit,
    onDraftsClick: () -> Unit,
    onMessagesClick: () -> Unit,
    onBadgesClick: () -> Unit,
    onFeedbackClick: () -> Unit,
    onInvitesClick: () -> Unit,
    onLdcClick: () -> Unit,
    onCdkClick: () -> Unit,
    onSettingsClick: () -> Unit,
) {
    val bookmarkCount = state.summary?.stats?.bookmarkCount ?: 0u
    val badgeCount = (state.summary?.badges?.size ?: 0).toUInt()
    FireSettingsCardRows(
        rows = listOf(
            FireListRowContent(
                icon = Icons.AutoMirrored.Filled.ViewList,
                title = "我的动态",
                iconWellColor = Color(0xFF8E8E93),
            ) to onActivityClick,
            FireListRowContent(
                icon = Icons.Filled.Bookmark,
                title = "我的书签",
                value = "${ProfileFormat.number(bookmarkCount)}条",
                iconWellColor = Color(0xFFFF9500),
            ) to onBookmarksClick,
            FireListRowContent(
                icon = Icons.Filled.History,
                title = "浏览历史",
                iconWellColor = Color(0xFFAF52DE),
            ) to onHistoryClick,
            FireListRowContent(
                icon = Icons.Filled.Description,
                title = "草稿箱",
                iconWellColor = Color(0xFF30B0C7),
            ) to onDraftsClick,
            FireListRowContent(
                icon = Icons.Filled.Email,
                title = "私信",
                iconWellColor = Color(0xFF007AFF),
            ) to onMessagesClick,
            FireListRowContent(
                icon = Icons.Filled.EmojiEvents,
                title = "我的勋章",
                value = "${ProfileFormat.number(badgeCount)}枚",
                iconWellColor = Color(0xFFDB9E29),
            ) to onBadgesClick,
        ),
    )
    Spacer(Modifier.height(12.dp))
    FireSettingsCardRows(
        rows = listOf(
            FireListRowContent(
                icon = Icons.Filled.Feedback,
                title = "反馈与建议",
                iconWellColor = Color(0xFFFF9500),
            ) to onFeedbackClick,
            FireListRowContent(
                icon = Icons.Filled.ConfirmationNumber,
                title = "邀请链接",
                iconWellColor = Color(0xFF34C759),
            ) to onInvitesClick,
            FireListRowContent(
                icon = Icons.Filled.CreditCard,
                title = "LDC 信用",
                iconWellColor = Color(0xFF32ADE6),
            ) to onLdcClick,
            FireListRowContent(
                icon = Icons.Filled.VpnKey,
                title = "CDK 连接",
                iconWellColor = MaterialTheme.fireExtended.accent,
            ) to onCdkClick,
            FireListRowContent(
                icon = Icons.Filled.Settings,
                title = "设置",
                iconWellColor = Color(0xFF8E8E93),
            ) to onSettingsClick,
        ),
    )
}

@Composable
private fun PublicActivitySection(
    state: ProfileUiState,
    onActivityClick: () -> Unit,
    onActivityItemClick: (UserActionState) -> Unit,
) {
    val colors = MaterialTheme.fireExtended
    Text(
        text = "最近动态",
        color = colors.tertiaryInk,
        fontSize = 12.sp,
        fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(start = 4.dp, bottom = 8.dp),
    )
    val recent = state.actions.take(4)
    FireSettingsCard {
        if (recent.isEmpty()) {
            Text(
                text = if (state.hasLoadedActionsOnce) "暂无动态" else "正在加载动态…",
                color = colors.tertiaryInk,
                modifier = Modifier.padding(16.dp),
            )
        } else {
            recent.forEach { action ->
                ProfileActivityRow(
                    action = action,
                    onClick = { onActivityItemClick(action) },
                )
            }
            Text(
                text = "查看全部动态",
                color = colors.accent,
                fontSize = 16.sp,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(onClick = onActivityClick)
                    .padding(horizontal = 14.dp, vertical = 14.dp),
            )
        }
    }
}

@Composable
fun ProfileHeaderCard(
    profile: UserProfileState,
    summary: UserSummaryState?,
) {
    val colors = MaterialTheme.fireExtended
    val displayName = profile.name?.trim()?.takeIf { it.isNotEmpty() } ?: profile.username
    val bio = HtmlText.toPlain(profile.bioCooked)
    FireSettingsCard {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                FireRemoteAvatar(
                    username = profile.username,
                    avatarTemplate = profile.avatarTemplate,
                    size = 56.dp,
                )
                Column(modifier = Modifier.padding(start = 12.dp)) {
                    Text(
                        text = displayName,
                        color = colors.ink,
                        fontSize = 20.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        text = "@${profile.username} · TL${profile.trustLevel}",
                        color = colors.subtleInk,
                        fontSize = 14.sp,
                    )
                    if (!bio.isNullOrBlank()) {
                        Text(
                            text = bio,
                            color = colors.subtleInk,
                            fontSize = 13.sp,
                            maxLines = 2,
                            modifier = Modifier.padding(top = 4.dp),
                        )
                    }
                }
            }
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(FireShapes.smallControl)
                    .background(colors.surfaceSecondary)
                    .padding(vertical = 8.dp),
            ) {
                ProfileStatColumn("粉丝", ProfileFormat.number(profile.totalFollowers), Modifier.weight(1f))
                ProfileStatColumn("获赞", ProfileFormat.number(summary?.stats?.likesReceived ?: 0u), Modifier.weight(1f))
                ProfileStatColumn("关注", ProfileFormat.number(profile.totalFollowing), Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun ProfileStatColumn(label: String, value: String, modifier: Modifier = Modifier) {
    val colors = MaterialTheme.fireExtended
    Column(modifier = modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(text = value, color = colors.ink, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
        Text(text = label, color = colors.tertiaryInk, fontSize = 12.sp)
    }
}

@Composable
fun ProfileActivityRow(
    action: UserActionState,
    onClick: () -> Unit,
) {
    val colors = MaterialTheme.fireExtended
    val excerpt = HtmlText.toPlain(action.excerpt)
    val title = excerpt ?: action.title ?: "动态 #${action.actionType}"
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 12.dp),
    ) {
        Text(text = title, color = colors.ink, fontSize = 16.sp, maxLines = 2)
        ProfileFormat.relativeTime(action.createdAt)?.let { time ->
            Text(
                text = time,
                color = colors.subtleInk,
                fontSize = 13.sp,
                modifier = Modifier.padding(top = 4.dp),
            )
        }
    }
}
