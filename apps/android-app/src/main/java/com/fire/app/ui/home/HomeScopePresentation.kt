package com.fire.app.ui.home

import com.fire.app.displayName
import uniffi.fire_uniffi_session.TopicCategoryState
import uniffi.fire_uniffi_types.TopicListKindState

data class HomeChildShortcut(
    val categoryId: ULong,
    val title: String,
    val isSelected: Boolean,
    val representsParentAll: Boolean,
)

data class HomeScopePresentation(
    val kind: TopicListKindState,
    val categoryId: ULong?,
    val tags: List<String>,
    val selectedCategory: TopicCategoryState?,
    val selectedParent: TopicCategoryState?,
    val selectedChild: TopicCategoryState?,
    val categoryPathTitle: String,
    val kindTitle: String,
    val categoryAccentHex: String?,
    val childShortcuts: List<HomeChildShortcut>,
    val showsChildShortcutStrip: Boolean,
) {
    val isDefaultCategory: Boolean get() = categoryId == null
    val isDefaultKind: Boolean get() = kind == TopicListKindState.LATEST
    val hasSelectedTags: Boolean get() = tags.isNotEmpty()
    val isDefaultScope: Boolean get() = isDefaultCategory && isDefaultKind && !hasSelectedTags

    companion object {
        fun make(
            kind: TopicListKindState,
            categoryId: ULong?,
            tags: List<String>,
            categories: List<TopicCategoryState>,
        ): HomeScopePresentation {
            val byId = categories.associateBy { it.id }
            val selected = categoryId?.let { byId[it] }
            val parent: TopicCategoryState?
            val child: TopicCategoryState?
            if (selected != null) {
                val parentId = selected.parentCategoryId
                val resolvedParent = parentId?.let { byId[it] }
                if (resolvedParent != null) {
                    parent = resolvedParent
                    child = selected
                } else {
                    parent = selected
                    child = null
                }
            } else {
                parent = null
                child = null
            }
            val shortcuts = childShortcuts(parent, categoryId, categories)
            return HomeScopePresentation(
                kind = kind,
                categoryId = categoryId,
                tags = tags,
                selectedCategory = selected,
                selectedParent = parent,
                selectedChild = child,
                categoryPathTitle = categoryPathTitle(parent, child),
                kindTitle = kind.fireTitle(),
                categoryAccentHex = (child ?: parent)?.colorHex,
                childShortcuts = shortcuts,
                showsChildShortcutStrip = shortcuts.isNotEmpty(),
            )
        }

        fun categoryPathTitle(
            parent: TopicCategoryState?,
            child: TopicCategoryState?,
        ): String {
            if (parent == null) return "全部"
            if (child == null) return parent.displayName()
            return "${parent.displayName()} / ${child.displayName()}"
        }

        fun parents(categories: List<TopicCategoryState>): List<TopicCategoryState> =
            categories.filter { it.parentCategoryId == null }

        fun children(
            parentId: ULong,
            categories: List<TopicCategoryState>,
        ): List<TopicCategoryState> = categories.filter { it.parentCategoryId == parentId }

        private fun childShortcuts(
            parent: TopicCategoryState?,
            selectedCategoryId: ULong?,
            categories: List<TopicCategoryState>,
        ): List<HomeChildShortcut> {
            if (parent == null) return emptyList()
            val children = children(parent.id, categories)
            if (children.isEmpty()) return emptyList()
            val all = HomeChildShortcut(
                categoryId = parent.id,
                title = "全部",
                isSelected = selectedCategoryId == parent.id,
                representsParentAll = true,
            )
            val childItems = children.map { child ->
                HomeChildShortcut(
                    categoryId = child.id,
                    title = child.displayName(),
                    isSelected = selectedCategoryId == child.id,
                    representsParentAll = false,
                )
            }
            return listOf(all) + childItems
        }
    }
}

fun TopicListKindState.fireTitle(): String = when (this) {
    TopicListKindState.LATEST -> "最新"
    TopicListKindState.NEW -> "最新发布"
    TopicListKindState.UNREAD -> "未读"
    TopicListKindState.UNSEEN -> "未看"
    TopicListKindState.HOT -> "热门"
    TopicListKindState.TOP -> "精华"
    TopicListKindState.PRIVATE_MESSAGES_INBOX -> "私信"
    TopicListKindState.PRIVATE_MESSAGES_SENT -> "已发"
}

val homeFeedKinds = listOf(
    TopicListKindState.LATEST,
    TopicListKindState.NEW,
    TopicListKindState.UNREAD,
    TopicListKindState.UNSEEN,
    TopicListKindState.HOT,
    TopicListKindState.TOP,
)
