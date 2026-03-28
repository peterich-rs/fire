import Foundation
import WebKit

@MainActor
final class FireAppViewModel: ObservableObject {
    @Published private(set) var session: SessionState = .placeholder()
    @Published var errorMessage: String?
    @Published var isPresentingLogin = false

    private let sessionStore: FireSessionStore?
    private let loginCoordinator: FireWebViewLoginCoordinator?

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
}
