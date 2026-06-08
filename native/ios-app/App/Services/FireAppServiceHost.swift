import Foundation

@MainActor
final class FireAppServiceHost {
    private unowned let owner: FireAppViewModel

    init(owner: FireAppViewModel) {
        self.owner = owner
    }

    var session: SessionState {
        owner.session
    }

    var canStartAuthenticatedMutation: Bool {
        owner.canStartAuthenticatedMutation
    }

    var topicDetailStore: FireTopicDetailStore? {
        owner.boundTopicDetailStore
    }

    func sessionStoreValue() async throws -> FireSessionStore {
        try await owner.sessionStoreValue()
    }

    func performWriteWithCloudflareRetry<T>(
        operationDescription: String = "执行当前操作",
        originURL: URL? = nil,
        _ operation: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        try await owner.performWriteWithCloudflareRetry(
            operationDescription: operationDescription,
            originURL: originURL,
            operation: operation
        )
    }

    func performWithCloudflareRecovery<T>(
        operation: String,
        _ request: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        try await owner.performWithCloudflareRecovery(
            operation: operation,
            work: request
        )
    }

    @discardableResult
    func handleRecoverableSessionErrorIfNeeded(_ error: Error) async -> Bool {
        await owner.handleRecoverableSessionErrorIfNeeded(error)
    }

    @discardableResult
    func handleInteractionError(_ error: Error) async -> Bool {
        await owner.handleInteractionError(error)
    }

    func clearErrorMessage() {
        owner.errorMessage = nil
    }
}
