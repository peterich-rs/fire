import Foundation
import UIKit
import WebKit

extension FireAppViewModel {
    func selectTopicKind(_ kind: TopicListKindState) {
        homeFeedStore?.selectTopicKind(kind)
    }

    func selectHomeCategory(_ categoryId: UInt64?) {
        homeFeedStore?.selectHomeCategory(categoryId)
    }

    func addHomeTag(_ tag: String) {
        homeFeedStore?.addHomeTag(tag)
    }

    func removeHomeTag(_ tag: String) {
        homeFeedStore?.removeHomeTag(tag)
    }

    func clearHomeTags() {
        homeFeedStore?.clearHomeTags()
    }

    var selectedHomeCategoryPresentation: FireTopicCategoryPresentation? {
        homeFeedStore?.selectedHomeCategoryPresentation
    }

    func refreshTopics() {
        homeFeedStore?.refreshTopics()
    }

    func refreshTopicsAsync() async {
        await homeFeedStore?.refreshTopicsAsync()
    }

    func loadMoreTopics() {
        homeFeedStore?.loadMoreTopics()
    }

    func applyHomeRowCountPatch(_ patch: TopicHomeRowCountPatchState) {
        homeFeedStore?.applyHomeRowCountPatch(patch)
    }

    func categoryPresentation(for categoryID: UInt64?) -> FireTopicCategoryPresentation? {
        if let category = homeFeedStore?.categoryPresentation(for: categoryID) {
            return category
        }
        guard let categoryID else { return nil }
        return session.bootstrap.categories.first(where: { $0.id == categoryID })
    }

    func allCategories() -> [FireTopicCategoryPresentation] {
        homeFeedStore?.allCategories ?? session.bootstrap.categories
    }

    func topTags() -> [String] {
        homeFeedStore?.topTags ?? session.bootstrap.topTags
    }

    var canTagTopics: Bool {
        homeFeedStore?.canTagTopics ?? session.bootstrap.canTagTopics
    }

    func fetchFilteredTopicList(query: TopicListQueryState) async throws -> TopicListState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchTopicList(query: query)
    }

    private func refreshTopicsIfPossible(force: Bool) async {
        await refreshHomeFeedIfPossible(force: force)
    }

    @discardableResult
    func refreshHomeFeedIfPossible(force: Bool) async -> Bool {
        await homeFeedStore?.refreshTopicsIfPossible(force: force) ?? false
    }
}
