import Foundation
import UIKit
import WebKit

extension FireAppViewModel {
    func recoverLoginCloudflareChallenge(in webView: WKWebView) async throws {
        let sessionStore = try await sessionStoreValue()
        try await completeLoginCloudflareChallenge(sessionStore: sessionStore)
        try await Task.sleep(for: .milliseconds(1_500))
        let loginCoordinator = try await loginCoordinatorValue()
        try await loginCoordinator.primeCookies(
            into: webView,
            targetURL: URL(string: "https://linux.do/")
        )
    }

    func ensureCloudflareClearance() async -> Bool {
        do {
            let sessionStore = try await sessionStoreValue()
            // Do not trust jar clearance that CF recently rejected (cold start / IP drift).
            if try await sessionStore.cloudflareClearanceIsTrusted() {
                return true
            }

            try await completeLoginCloudflareChallenge(sessionStore: sessionStore)
            try await Task.sleep(for: .milliseconds(1_500))
            return try await sessionStore.cloudflareClearanceIsTrusted()
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func loginCoordinatorForDialog() async throws -> FireWebViewLoginCoordinator {
        try await loginCoordinatorValue()
    }

    func probeLoginSyncReadiness(from webView: WKWebView) async throws -> FireLoginSyncReadiness {
        let loginCoordinator = try await loginCoordinatorValue()
        return try await loginCoordinator.probeLoginSyncReadiness(from: webView)
    }

    private func completeLoginCloudflareChallenge(
        sessionStore: FireSessionStore
    ) async throws {
        let challengeCoordinator = FireCloudflareChallengeCoordinator(sessionStore: sessionStore)
        let result = await challengeCoordinator.completeManualVerification(originURL: "https://linux.do/")
        guard result.completed else {
            throw FireLoginPreparationError.cloudflareVerificationIncomplete
        }

        _ = try await sessionStore.completeCloudflareChallenge(
            cookies: result.cookies,
            freshCfClearance: result.freshCfClearance,
            browserUserAgent: result.browserUserAgent
        )
    }

    private func prepareLoginNetworkAccess() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true

        let session = URLSession(configuration: configuration)
        var request = URLRequest(url: loginURL)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (_, response) = try await session.data(for: request)
        guard response is HTTPURLResponse else {
            throw FireLoginPreparationError.invalidResponse
        }
    }

    private func preloadLoginCoordinator() async throws {
        if let loginCoordinatorPreloader {
            try await loginCoordinatorPreloader()
            return
        }

        _ = try await loginCoordinatorValue()
    }

    private func warmLoginNetworkAccess() async {
        if let loginNetworkWarmup {
            await loginNetworkWarmup()
            return
        }

        do {
            try await prepareLoginNetworkAccess()
        } catch {
            FireAPMManager.shared.recordBreadcrumb(
                level: "warn",
                target: "auth.login",
                message: "login network warmup failed: \(error.localizedDescription)"
            )
        }
    }

    func refreshLoginSyncReadiness(from webView: WKWebView) {
        loginSyncReadinessTask?.cancel()
        loginSyncReadinessTask = Task { [weak self] in
            guard let self else { return }
            do {
                let coordinator = try await loginCoordinatorValue()
                let readiness = try await coordinator.probeLoginSyncReadiness(from: webView)
                guard !Task.isCancelled else { return }
                let previous = canSyncLoginSession
                cachedLoginSyncReadiness = readiness.isReady
                    ? CachedLoginSyncReadiness(
                        currentURL: webView.url?.absoluteString,
                        readiness: readiness
                    )
                    : nil
                canSyncLoginSession = readiness.isReady
                if previous != readiness.isReady {
                    FireAPMManager.shared.recordBreadcrumb(
                        target: "auth.login",
                        message: readiness.isReady
                            ? "login sync readiness satisfied"
                            : "login sync readiness cleared"
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                canSyncLoginSession = false
                cachedLoginSyncReadiness = nil
            }
        }
    }

    func setWebKitCookie(_ cookie: HTTPCookie, in store: WKHTTPCookieStore) async {
        await withCheckedContinuation { continuation in
            store.setCookie(cookie) {
                continuation.resume()
            }
        }
    }

    func loginCoordinatorValue() async throws -> FireWebViewLoginCoordinator {
        if let loginCoordinator {
            return loginCoordinator
        }

        let sessionStore = try await sessionStoreValue()
        await configureAuthenticatedWriteHostResyncProvider(with: sessionStore)
        guard let loginCoordinator else {
            throw CancellationError()
        }
        return loginCoordinator
    }
}
