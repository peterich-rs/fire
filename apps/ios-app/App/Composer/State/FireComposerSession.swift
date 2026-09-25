import Foundation

@MainActor
final class FireComposerSession {
    unowned let appViewModel: FireAppViewModel

    init(appViewModel: FireAppViewModel) {
        self.appViewModel = appViewModel
    }

    static func isPendingReview(_ error: Error) -> Bool {
        error.localizedDescription.localizedCaseInsensitiveContains("pending review")
    }

    static func normalizedTitle(_ title: String) throws -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FireTopicInteractionError.emptyReply
        }
        return trimmed
    }

    static func normalizedBody(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FireTopicInteractionError.emptyReply
        }
        return trimmed
    }

    static func normalizedRecipients(_ recipients: [String]) throws -> [String] {
        let normalized = recipients
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else {
            throw FireTopicInteractionError.emptyReply
        }
        return normalized
    }

    func createTopic(
        title: String,
        raw: String,
        categoryID: UInt64,
        tags: [String]
    ) async throws -> UInt64 {
        let trimmedTitle = try Self.normalizedTitle(title)
        let trimmedRaw = try Self.normalizedBody(raw)
        let sessionStore = try await appViewModel.sessionStoreValue()
        guard appViewModel.canStartAuthenticatedMutation else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }

        do {
            appViewModel.errorMessage = nil
            let topicID = try await appViewModel.performWriteWithCloudflareRetry {
                try await sessionStore.createTopic(
                    title: trimmedTitle,
                    raw: trimmedRaw,
                    categoryID: categoryID,
                    tags: tags
                )
            }
            await appViewModel.syncSessionSnapshotIfAvailable(from: sessionStore)
            await appViewModel.refreshHomeFeedIfPossible(force: true)
            return topicID
        } catch {
            _ = await appViewModel.handleInteractionError(error)
            throw error
        }
    }

    func createPrivateMessage(
        title: String,
        raw: String,
        targetRecipients: [String]
    ) async throws -> UInt64 {
        let trimmedTitle = try Self.normalizedTitle(title)
        let trimmedRaw = try Self.normalizedBody(raw)
        let recipients = try Self.normalizedRecipients(targetRecipients)
        let sessionStore = try await appViewModel.sessionStoreValue()
        guard appViewModel.canStartAuthenticatedMutation else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }

        do {
            appViewModel.errorMessage = nil
            let topicID = try await appViewModel.performWriteWithCloudflareRetry {
                try await sessionStore.createPrivateMessage(
                    title: trimmedTitle,
                    raw: trimmedRaw,
                    targetRecipients: recipients
                )
            }
            await appViewModel.syncSessionSnapshotIfAvailable(from: sessionStore)
            return topicID
        } catch {
            _ = await appViewModel.handleInteractionError(error)
            throw error
        }
    }

    func updateTopic(
        topicID: UInt64,
        title: String,
        categoryID: UInt64,
        tags: [String]
    ) async throws {
        let trimmedTitle = try Self.normalizedTitle(title)
        guard appViewModel.canStartAuthenticatedMutation else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }

        do {
            appViewModel.errorMessage = nil
            if appViewModel.topicDetailStore != nil {
                try await appViewModel.performWriteWithCloudflareRetry {
                    try await self.appViewModel.topicDetailStore?.updateTopic(
                        topicId: topicID,
                        title: trimmedTitle,
                        categoryId: categoryID,
                        tags: tags
                    )
                }
            } else {
                let sessionStore = try await appViewModel.sessionStoreValue()
                try await appViewModel.performWriteWithCloudflareRetry {
                    try await sessionStore.updateTopic(
                        topicID: topicID,
                        title: trimmedTitle,
                        categoryID: categoryID,
                        tags: tags
                    )
                }
                await appViewModel.syncSessionSnapshotIfAvailable(from: sessionStore)
            }
            await appViewModel.refreshHomeFeedIfPossible(force: true)
        } catch {
            _ = await appViewModel.handleInteractionError(error)
            throw error
        }
    }

    func saveDraft(
        draftKey: String,
        data: DraftDataState,
        sequence: UInt32
    ) async throws -> UInt32 {
        let sessionStore = try await appViewModel.sessionStoreValue()
        return try await appViewModel.performWriteWithCloudflareRetry {
            try await sessionStore.saveDraft(
                draftKey: draftKey,
                data: data,
                sequence: sequence
            )
        }
    }

    func deleteDraft(draftKey: String, sequence: UInt32? = nil) async throws {
        let sessionStore = try await appViewModel.sessionStoreValue()
        try await appViewModel.performWriteWithCloudflareRetry {
            try await sessionStore.deleteDraft(draftKey: draftKey, sequence: sequence)
        }
    }

    func uploadImage(
        fileName: String,
        mimeType: String?,
        bytes: Data
    ) async throws -> UploadResultState {
        let sessionStore = try await appViewModel.sessionStoreValue()
        return try await appViewModel.performWriteWithCloudflareRetry {
            try await sessionStore.uploadImage(
                fileName: fileName,
                mimeType: mimeType,
                bytes: bytes
            )
        }
    }

    func lookupUploadUrls(shortUrls: [String]) async throws -> [ResolvedUploadUrlState] {
        let sessionStore = try await appViewModel.sessionStoreValue()
        return try await appViewModel.performWriteWithCloudflareRetry {
            try await sessionStore.lookupUploadUrls(shortUrls: shortUrls)
        }
    }
}
