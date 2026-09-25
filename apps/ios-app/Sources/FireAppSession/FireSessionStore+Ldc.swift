import Foundation

extension FireSessionStore {
    public func ldcAuthorizationUrl() async throws -> LdcAuthorizationUrlState {
        try await runPersistingSessionChanges {
            try await core.ldc().ldcAuthorizationUrl()
        }
    }

    public func ldcApprovalLink(authorizationURL: String) async throws -> String {
        try await runPersistingSessionChanges {
            try await core.ldc().ldcApprovalLink(authorizationUrl: authorizationURL)
        }
    }

    public func ldcApprove(approvePath: String) async throws -> LdcApprovalStatusState {
        try await runPersistingSessionChanges {
            try await core.ldc().ldcApprove(approvePath: approvePath)
        }
    }

    public func ldcCallback(code: String, state: String) async throws {
        try await runPersistingSessionChanges {
            try await core.ldc().ldcCallback(code: code, state: state)
        }
    }

    public func ldcUserInfo() async throws -> LdcUserInfoState {
        try await runPersistingSessionChanges {
            try await core.ldc().ldcUserInfo()
        }
    }

    public func ldcLogout() async throws {
        try await runPersistingSessionChanges {
            try await core.ldc().ldcLogout()
        }
    }

    public func cdkAuthorizationUrl() async throws -> CdkAuthorizationUrlState {
        try await runPersistingSessionChanges {
            try await core.ldc().cdkAuthorizationUrl()
        }
    }

    public func cdkApprovalLink(authorizationURL: String) async throws -> String {
        try await runPersistingSessionChanges {
            try await core.ldc().cdkApprovalLink(authorizationUrl: authorizationURL)
        }
    }

    public func cdkApprove(approvePath: String) async throws -> LdcApprovalStatusState {
        try await runPersistingSessionChanges {
            try await core.ldc().cdkApprove(approvePath: approvePath)
        }
    }

    public func cdkCallback(code: String, state: String) async throws {
        try await runPersistingSessionChanges {
            try await core.ldc().cdkCallback(code: code, state: state)
        }
    }

    public func cdkUserInfo() async throws -> CdkUserInfoState {
        try await runPersistingSessionChanges {
            try await core.ldc().cdkUserInfo()
        }
    }

    public func cdkLogout() async throws {
        try await runPersistingSessionChanges {
            try await core.ldc().cdkLogout()
        }
    }
}
