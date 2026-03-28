import Foundation
import WebKit

private enum FireLoginPreparationError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Unable to prepare login network access."
        }
    }
}

@MainActor
final class FireAppViewModel: ObservableObject {
    @Published private(set) var session: SessionState = .placeholder()
    @Published var errorMessage: String?
    @Published var isPresentingLogin = false
    @Published var isPreparingLogin = false

    private let sessionStore: FireSessionStore?
    private let loginCoordinator: FireWebViewLoginCoordinator?
    private let loginURL = URL(string: "https://linux.do")!

    init() {
        do {
            let sessionStore = try FireSessionStore()
            self.sessionStore = sessionStore
            self.loginCoordinator = FireWebViewLoginCoordinator(sessionStore: sessionStore)
        } catch {
            self.sessionStore = nil
            self.loginCoordinator = nil
            self.errorMessage = error.localizedDescription
        }
    }

    func loadInitialState() {
        guard let loginCoordinator, let sessionStore else {
            return
        }

        Task {
            do {
                if let restored = try await loginCoordinator.restorePersistedSessionIfAvailable() {
                    session = restored
                } else {
                    session = await sessionStore.snapshot()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func refreshSession() {
        guard let sessionStore else {
            return
        }

        Task {
            session = await sessionStore.snapshot()
        }
    }

    func openLogin() {
        guard !isPreparingLogin else {
            return
        }

        errorMessage = nil
        isPreparingLogin = true

        Task {
            defer { isPreparingLogin = false }

            do {
                try await prepareLoginNetworkAccess()
                isPresentingLogin = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func completeLogin(from webView: WKWebView) {
        guard let loginCoordinator else {
            return
        }

        Task {
            do {
                session = try await loginCoordinator.completeLogin(from: webView)
                isPresentingLogin = false
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func refreshBootstrap() {
        guard let sessionStore else {
            return
        }

        Task {
            do {
                session = try await sessionStore.refreshBootstrapIfNeeded()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func logout() {
        guard let loginCoordinator else {
            return
        }

        Task {
            do {
                session = try await loginCoordinator.logout()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
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
}
