package com.fire.app.ui.notifications

import uniffi.fire_uniffi_notifications.NotificationItemState

object NotificationPresentation {
    fun resolvedUsername(item: NotificationItemState): String? {
        return listOf(
            item.data.displayUsername,
            item.data.username,
            item.data.originalUsername,
        ).firstNotNullOfOrNull { value ->
            value?.trim()?.takeIf { it.isNotEmpty() && !it.equals("null", ignoreCase = true) }
        }
    }

    fun displayDescription(item: NotificationItemState): String {
        val actor = resolvedUsername(item) ?: "Someone"
        val title = item.fancyTitle ?: item.data.topicTitle ?: ""
        val suffix = if (title.isEmpty()) "" else "「$title」"
        return when (item.notificationType) {
            1 -> "$actor 提到了你$suffix"
            2 -> "$actor 回复了你$suffix"
            3 -> "$actor 引用了你的帖子$suffix"
            4 -> "$actor 编辑了帖子$suffix"
            5 -> likedDescription(item, actor, suffix)
            6 -> "$actor 给你发了私信$suffix"
            7 -> "$actor 邀请你加入私信$suffix"
            8 -> "$actor 接受了你的邀请"
            9 -> "$actor 发帖$suffix"
            10 -> "$actor 移动了帖子$suffix"
            11 -> "$actor 链接了你的帖子$suffix"
            12 -> {
                val badge = item.data.badgeName ?: title
                if (badge.isEmpty()) "你获得了新徽章" else "你获得了徽章「$badge」"
            }
            13 -> "$actor 邀请你参与话题$suffix"
            14 -> title.ifEmpty { "自定义通知" }
            15 -> "$actor 提及了你所在的群组$suffix"
            16 -> {
                val count = item.data.inboxCount?.toIntOrNull() ?: 0
                val group = item.data.groupName.orEmpty()
                "$group 有 $count 条新消息"
            }
            17 -> "新话题$suffix"
            18 -> "话题提醒$suffix"
            19 -> {
                val count = item.data.count ?: 0u
                "$actor 等 $count 人赞了你的多篇帖子"
            }
            20 -> "你的帖子已通过审核$suffix"
            22 -> {
                val group = item.data.groupName.orEmpty()
                if (group.isEmpty()) "加群申请已通过" else "你已加入群组「$group」"
            }
            24 -> "书签提醒$suffix"
            25 -> "$actor 对你的帖子使用了表情$suffix"
            800 -> "$actor 关注了你"
            801 -> "$actor 发布了新话题$suffix"
            802 -> "$actor 回复了话题$suffix"
            900 -> "圈子动态$suffix"
            else -> title.ifEmpty { "新通知" }
        }
    }

    private fun likedDescription(item: NotificationItemState, actor: String, suffix: String): String {
        val count = item.data.count ?: 1u
        return if (count.toInt() <= 1) {
            "$actor 赞了你的帖子$suffix"
        } else {
            val second = item.data.username2?.takeIf { it.isNotBlank() }
            if (second != null) {
                "$actor 和 $second 赞了你的帖子$suffix"
            } else {
                "$actor 等 $count 人赞了你的帖子$suffix"
            }
        }
    }
}
