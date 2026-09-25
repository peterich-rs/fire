import XCTest
@testable import Fire

final class FireHomeScopePresentationTests: XCTestCase {
    func testDefaultScopeUsesAllAndHidesChildStrip() {
        let presentation = FireHomeScopePresentation.make(
            kind: .latest,
            categoryID: nil,
            tags: [],
            categories: sampleCategories()
        )

        XCTAssertEqual(presentation.categoryPathTitle, "全部")
        XCTAssertEqual(presentation.kindTitle, "最新")
        XCTAssertNil(presentation.selectedCategory)
        XCTAssertNil(presentation.selectedParent)
        XCTAssertNil(presentation.selectedChild)
        XCTAssertFalse(presentation.showsChildShortcutStrip)
        XCTAssertTrue(presentation.childShortcuts.isEmpty)
        XCTAssertTrue(presentation.isDefaultScope)
    }

    func testParentSelectionShowsParentPathAndChildShortcuts() {
        let presentation = FireHomeScopePresentation.make(
            kind: .hot,
            categoryID: 10,
            tags: ["rust"],
            categories: sampleCategories()
        )

        XCTAssertEqual(presentation.categoryPathTitle, "开发调优")
        XCTAssertEqual(presentation.selectedParent?.id, 10)
        XCTAssertNil(presentation.selectedChild)
        XCTAssertTrue(presentation.showsChildShortcutStrip)
        XCTAssertEqual(presentation.childShortcuts.map(\.title), ["全部", "Rust", "前端"])
        XCTAssertEqual(
            presentation.childShortcuts.first(where: \.representsParentAll)?.isSelected,
            true
        )
        XCTAssertEqual(presentation.kindTitle, "热门")
        XCTAssertFalse(presentation.isDefaultScope)
        XCTAssertEqual(presentation.categoryAccentHex, "F57338")
    }

    func testChildSelectionBuildsParentChildPathAndSelectsShortcut() {
        let presentation = FireHomeScopePresentation.make(
            kind: .latest,
            categoryID: 12,
            tags: [],
            categories: sampleCategories()
        )

        XCTAssertEqual(presentation.categoryPathTitle, "开发调优 / 前端")
        XCTAssertEqual(presentation.selectedParent?.id, 10)
        XCTAssertEqual(presentation.selectedChild?.id, 12)
        XCTAssertEqual(presentation.selectedCategory?.id, 12)
        XCTAssertTrue(presentation.showsChildShortcutStrip)

        let selected = presentation.childShortcuts.first(where: \.isSelected)
        XCTAssertEqual(selected?.categoryID, 12)
        XCTAssertEqual(selected?.representsParentAll, false)
        XCTAssertEqual(
            presentation.childShortcuts.first(where: \.representsParentAll)?.isSelected,
            false
        )
    }

    func testParentWithoutChildrenHidesShortcutStrip() {
        let presentation = FireHomeScopePresentation.make(
            kind: .latest,
            categoryID: 20,
            tags: [],
            categories: sampleCategories()
        )

        XCTAssertEqual(presentation.categoryPathTitle, "未分类")
        XCTAssertFalse(presentation.showsChildShortcutStrip)
        XCTAssertTrue(presentation.childShortcuts.isEmpty)
    }

    func testParentsAndChildrenHelpers() {
        let categories = sampleCategories()
        let parents = FireHomeScopePresentation.parents(from: categories)
        XCTAssertEqual(parents.map(\.id), [10, 20])
        XCTAssertEqual(
            FireHomeScopePresentation.children(of: 10, in: categories).map(\.id),
            [11, 12]
        )
        XCTAssertTrue(FireHomeScopePresentation.children(of: 20, in: categories).isEmpty)
    }

    private func sampleCategories() -> [TopicCategoryState] {
        [
            makeCategory(id: 10, name: "开发调优", parent: nil, color: "F57338"),
            makeCategory(id: 11, name: "Rust", parent: 10, color: "DEA584"),
            makeCategory(id: 12, name: "前端", parent: 10, color: "61AFEF"),
            makeCategory(id: 20, name: "未分类", parent: nil, color: "888888"),
        ]
    }

    private func makeCategory(
        id: UInt64,
        name: String,
        parent: UInt64?,
        color: String?
    ) -> TopicCategoryState {
        TopicCategoryState(
            id: id,
            name: name,
            slug: name.lowercased(),
            parentCategoryId: parent,
            colorHex: color,
            textColorHex: nil,
            topicTemplate: nil,
            minimumRequiredTags: 0,
            requiredTagGroups: [],
            allowedTags: [],
            permission: 1,
            notificationLevel: nil
        )
    }
}
