import Foundation

extension FireSessionStore {
    public func fetchDrafts(
        offset: UInt32? = nil,
        limit: UInt32? = nil
    ) async throws -> DraftListResponseState {
        try await runPersistingSessionChanges {
            try await core.notifications().fetchDrafts(offset: offset, limit: limit)
        }
    }

    public func fetchDraft(draftKey: String) async throws -> DraftState? {
        try await runPersistingSessionChanges {
            try await core.notifications().fetchDraft(draftKey: draftKey)
        }
    }

    public func saveDraft(
        draftKey: String,
        data: DraftDataState,
        sequence: UInt32
    ) async throws -> UInt32 {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.notifications().saveDraft(draftKey: draftKey, data: data, sequence: sequence)
        }
    }

    public func deleteDraft(
        draftKey: String,
        sequence: UInt32? = nil
    ) async throws {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.notifications().deleteDraft(draftKey: draftKey, sequence: sequence)
        }
    }

    public func createReply(
        topicID: UInt64,
        raw: String,
        replyToPostNumber: UInt32?
    ) async throws -> TopicPostState {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.topics().createReply(
                input: TopicReplyRequestState(
                    topicId: topicID,
                    raw: raw,
                    replyToPostNumber: replyToPostNumber
                )
            )
        }
    }

    public func updatePost(
        postID: UInt64,
        raw: String,
        editReason: String? = nil
    ) async throws -> TopicPostState {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.topics().updatePost(
                input: PostUpdateRequestState(
                    postId: postID,
                    raw: raw,
                    editReason: editReason
                )
            )
        }
    }

    public func deletePost(postID: UInt64) async throws {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.topics().deletePost(postId: postID)
        }
    }

    public func recoverPost(postID: UInt64) async throws {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.topics().recoverPost(postId: postID)
        }
    }

    public func createTopic(
        title: String,
        raw: String,
        categoryID: UInt64,
        tags: [String]
    ) async throws -> UInt64 {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.topics().createTopic(
                input: TopicCreateRequestState(
                    title: title,
                    raw: raw,
                    categoryId: categoryID,
                    tags: tags
                )
            )
        }
    }

    public func createPrivateMessage(
        title: String,
        raw: String,
        targetRecipients: [String]
    ) async throws -> UInt64 {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.topics().createPrivateMessage(
                input: PrivateMessageCreateRequestState(
                    title: title,
                    raw: raw,
                    targetRecipients: targetRecipients
                )
            )
        }
    }

    public func updateTopic(
        topicID: UInt64,
        title: String,
        categoryID: UInt64,
        tags: [String]
    ) async throws {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.topics().updateTopic(
                input: TopicUpdateRequestState(
                    topicId: topicID,
                    title: title,
                    categoryId: categoryID,
                    tags: tags
                )
            )
        }
    }

    public func uploadImage(
        fileName: String,
        mimeType: String?,
        bytes: Data
    ) async throws -> UploadResultState {
        try await runAuthenticatedWritePersistingSessionChanges {
            try await core.topics().uploadImage(
                input: UploadImageRequestState(
                    fileName: fileName,
                    mimeType: mimeType,
                    bytes: bytes
                )
            )
        }
    }

    public func lookupUploadUrls(shortUrls: [String]) async throws -> [ResolvedUploadUrlState] {
        try await runPersistingSessionChanges {
            try await core.topics().lookupUploadUrls(shortUrls: shortUrls)
        }
    }
}
