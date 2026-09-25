import Foundation
import UIKit
import WebKit

extension FireAppViewModel {
    var canStartAuthenticatedMutation: Bool {
        session.readiness.canReadAuthenticatedApi
    }

    func fetchPrivateMessages(
        kind: TopicListKindState,
        page: UInt32? = nil
    ) async throws -> TopicListState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchTopicList(
            query: TopicListQueryState(
                kind: kind,
                page: page,
                topicIds: [],
                order: nil,
                ascending: nil,
                categorySlug: nil,
                categoryId: nil,
                parentCategorySlug: nil,
                tag: nil,
                additionalTags: [],
                matchAllTags: false
            )
        )
    }

    func enabledReactionOptions() -> [FireReactionOption] {
        FireTopicPresentation.enabledReactionOptions(from: session.bootstrap.enabledReactionIds)
    }

    func submitReply(
        topicId: UInt64,
        raw: String,
        replyToPostNumber: UInt32?,
        scrollToCreated: Bool = false
    ) async throws {
        guard let topicDetailStore else {
            throw FireTopicInteractionError.unavailable
        }
        try await topicDetailStore.submitReply(
            topicId: topicId,
            raw: raw,
            replyToPostNumber: replyToPostNumber,
            scrollToCreated: scrollToCreated
        )
    }

    func createTopic(
        title: String,
        raw: String,
        categoryID: UInt64,
        tags: [String]
    ) async throws -> UInt64 {
        try await composerSession.createTopic(
            title: title,
            raw: raw,
            categoryID: categoryID,
            tags: tags
        )
    }

    func createPrivateMessage(
        title: String,
        raw: String,
        targetRecipients: [String]
    ) async throws -> UInt64 {
        try await composerSession.createPrivateMessage(
            title: title,
            raw: raw,
            targetRecipients: targetRecipients
        )
    }

    func updateTopic(
        topicID: UInt64,
        title: String,
        categoryID: UInt64,
        tags: [String]
    ) async throws {
        try await composerSession.updateTopic(
            topicID: topicID,
            title: title,
            categoryID: categoryID,
            tags: tags
        )
    }

    func fetchPost(postID: UInt64) async throws -> TopicPostState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchPost(postID: postID)
    }

    func updatePost(
        topicID: UInt64,
        postID: UInt64,
        raw: String,
        editReason: String? = nil
    ) async throws {
        guard let topicDetailStore else {
            throw FireTopicInteractionError.unavailable
        }
        try await topicDetailStore.updatePost(
            topicId: topicID,
            postId: postID,
            raw: raw,
            editReason: editReason
        )
        await refreshHomeFeedIfPossible(force: false)
    }

    func fetchDrafts(
        offset: UInt32? = nil,
        limit: UInt32? = nil
    ) async throws -> DraftListResponseState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchDrafts(offset: offset, limit: limit)
    }

    func fetchReadHistory(page: UInt32? = nil) async throws -> TopicListState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchReadHistory(page: page)
    }

    func fetchDraft(draftKey: String) async throws -> DraftState? {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchDraft(draftKey: draftKey)
    }

    func saveDraft(
        draftKey: String,
        data: DraftDataState,
        sequence: UInt32
    ) async throws -> UInt32 {
        try await composerSession.saveDraft(
            draftKey: draftKey,
            data: data,
            sequence: sequence
        )
    }

    func deleteDraft(
        draftKey: String,
        sequence: UInt32? = nil
    ) async throws {
        try await composerSession.deleteDraft(draftKey: draftKey, sequence: sequence)
    }

    func uploadImage(
        fileName: String,
        mimeType: String?,
        bytes: Data
    ) async throws -> UploadResultState {
        try await composerSession.uploadImage(
            fileName: fileName,
            mimeType: mimeType,
            bytes: bytes
        )
    }

    func lookupUploadUrls(shortUrls: [String]) async throws -> [ResolvedUploadUrlState] {
        try await composerSession.lookupUploadUrls(shortUrls: shortUrls)
    }
}
