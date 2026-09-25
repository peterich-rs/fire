import Foundation
import UIKit
import WebKit

extension FireAppViewModel {
    func currentSessionEpoch() async throws -> UInt64 {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.currentSessionEpoch()
    }

    func authDiagnosticsLogger() async -> FireHostLogger? {
        if let sessionStore {
            return sessionStore.makeLogger(target: Self.authDiagnosticsLogTarget)
        }
        guard let sessionStore = try? await sessionStoreValue() else {
            return nil
        }
        return sessionStore.makeLogger(target: Self.authDiagnosticsLogTarget)
    }

    func topicDetailLogger() -> FireHostLogger? {
        sessionStore?.makeLogger(target: Self.topicDetailLogTarget)
    }

    func topicRouteLogger() -> FireHostLogger? {
        sessionStore?.makeLogger(target: Self.topicRouteLogTarget)
    }
}
