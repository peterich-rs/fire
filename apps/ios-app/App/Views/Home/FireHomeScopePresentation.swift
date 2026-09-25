import Foundation

/// Derived home-scope chrome for the status bar / child shortcut strip / panel.
/// Pure presentation over `FireHomeFeedStore` fields — not a second source of truth.
struct FireHomeScopePresentation: Equatable, Sendable {
    var kind: TopicListKindState
    var categoryID: UInt64?
    var tags: [String]

    var selectedCategory: FireTopicCategoryPresentation?
    /// Parent of the selection when a child is selected; the category itself when a parent is selected.
    var selectedParent: FireTopicCategoryPresentation?
    var selectedChild: FireTopicCategoryPresentation?

    /// `全部` | parent name | `parent / child`
    var categoryPathTitle: String
    var kindTitle: String
    var categoryAccentHex: String?

    var childShortcuts: [FireHomeChildShortcut]
    var showsChildShortcutStrip: Bool

    var isDefaultCategory: Bool { categoryID == nil }
    var isDefaultKind: Bool { kind == .latest }
    var hasSelectedTags: Bool { !tags.isEmpty }
    var isDefaultScope: Bool { isDefaultCategory && isDefaultKind && !hasSelectedTags }

    static func make(
        kind: TopicListKindState,
        categoryID: UInt64?,
        tags: [String],
        categories: [FireTopicCategoryPresentation]
    ) -> Self {
        let byID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let selected = categoryID.flatMap { byID[$0] }
        let parent: FireTopicCategoryPresentation?
        let child: FireTopicCategoryPresentation?
        if let selected {
            if let parentID = selected.parentCategoryId, let resolvedParent = byID[parentID] {
                parent = resolvedParent
                child = selected
            } else {
                parent = selected
                child = nil
            }
        } else {
            parent = nil
            child = nil
        }

        let pathTitle = categoryPathTitle(parent: parent, child: child)
        let shortcuts = childShortcuts(for: parent, selectedCategoryID: categoryID, categories: categories)

        return FireHomeScopePresentation(
            kind: kind,
            categoryID: categoryID,
            tags: tags,
            selectedCategory: selected,
            selectedParent: parent,
            selectedChild: child,
            categoryPathTitle: pathTitle,
            kindTitle: kind.title,
            categoryAccentHex: (child ?? parent)?.colorHex,
            childShortcuts: shortcuts,
            showsChildShortcutStrip: !shortcuts.isEmpty
        )
    }

    static func categoryPathTitle(
        parent: FireTopicCategoryPresentation?,
        child: FireTopicCategoryPresentation?
    ) -> String {
        guard let parent else { return "全部" }
        guard let child else { return parent.displayName }
        return "\(parent.displayName) / \(child.displayName)"
    }

    static func parents(from categories: [FireTopicCategoryPresentation]) -> [FireTopicCategoryPresentation] {
        categories.filter { $0.parentCategoryId == nil }
    }

    static func children(
        of parentID: UInt64,
        in categories: [FireTopicCategoryPresentation]
    ) -> [FireTopicCategoryPresentation] {
        categories.filter { $0.parentCategoryId == parentID }
    }

    private static func childShortcuts(
        for parent: FireTopicCategoryPresentation?,
        selectedCategoryID: UInt64?,
        categories: [FireTopicCategoryPresentation]
    ) -> [FireHomeChildShortcut] {
        guard let parent else { return [] }
        let children = children(of: parent.id, in: categories)
        guard !children.isEmpty else { return [] }

        var shortcuts: [FireHomeChildShortcut] = [
            FireHomeChildShortcut(
                categoryID: parent.id,
                title: "全部",
                isSelected: selectedCategoryID == parent.id,
                representsParentAll: true
            ),
        ]
        shortcuts += children.map { child in
            FireHomeChildShortcut(
                categoryID: child.id,
                title: child.displayName,
                isSelected: selectedCategoryID == child.id,
                representsParentAll: false
            )
        }
        return shortcuts
    }
}

struct FireHomeChildShortcut: Equatable, Hashable, Sendable, Identifiable {
    /// Target category id committed to the store when tapped.
    /// For the synthetic "全部" shortcut this is the parent id.
    var categoryID: UInt64
    var title: String
    var isSelected: Bool
    var representsParentAll: Bool

    var id: String {
        representsParentAll ? "parent-all:\(categoryID)" : "child:\(categoryID)"
    }
}

extension FireHomeFeedStore {
    var scopePresentation: FireHomeScopePresentation {
        FireHomeScopePresentation.make(
            kind: selectedTopicKind,
            categoryID: selectedHomeCategoryId,
            tags: selectedHomeTags,
            categories: allCategories
        )
    }

    func clearHomeCategory() {
        selectHomeCategory(nil)
    }

    func clearHomeScopeFilters() {
        let hadCategory = selectedHomeCategoryId != nil
        let hadTags = !selectedHomeTags.isEmpty
        guard hadCategory || hadTags else { return }
        if hadTags {
            // Category change already clears tags; if only tags are set, clear them directly.
            if hadCategory {
                selectHomeCategory(nil)
            } else {
                clearHomeTags()
            }
        } else {
            selectHomeCategory(nil)
        }
    }
}
