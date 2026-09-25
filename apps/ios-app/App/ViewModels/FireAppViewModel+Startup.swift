import Foundation
import UIKit
import WebKit

extension FireAppViewModel {
    func loadInitialState() {
        initialStateLoadGeneration &+= 1
        let generation = initialStateLoadGeneration

        initialStateTask?.cancel()
        initialStateLoadingDelayTask?.cancel()
        FireCfClearanceRefreshService.shared.setLoginStateConfirmed(false)
        isBootstrappingSession = true
        isStartupLoadingVisible = false

        initialStateLoadingDelayTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }

            guard let self else { return }
            guard self.initialStateLoadGeneration == generation else { return }
            guard self.isBootstrappingSession else { return }
            self.isStartupLoadingVisible = true
        }

        initialStateTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.finishInitialStateLoading(generation: generation)
            }

            do {
                try await FireAPMManager.shared.withSpan(.appLaunchRestoreSession) {
                    let sessionStore = try await self.sessionStoreValue()
                    guard self.initialStateLoadGeneration == generation else { return }
                    self.errorMessage = nil
                    _ = try await sessionStore.prepareStartupSession()
                    guard self.initialStateLoadGeneration == generation else { return }
                    Task {
                        try? await sessionStore.ensurePreloadedDataLoaded()
                    }
                }
            } catch {
                guard self.initialStateLoadGeneration == generation else { return }
                if await self.handleRecoverableSessionErrorIfNeeded(error) {
                    return
                }
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func completeStartupAfterPreheat() async {
        let generation = initialStateLoadGeneration
        do {
            let sessionStore = try await sessionStoreValue()
            guard self.initialStateLoadGeneration == generation else { return }
            self.errorMessage = nil
            let loginState = try await sessionStore.determineLoginStateWithProbe()
            guard self.initialStateLoadGeneration == generation else { return }
            switch loginState {
            case .loggedIn:
                FireCfClearanceRefreshService.shared.setLoginStateConfirmed(true)
                try await sessionStore.triggerAppStateRefresh(
                    .sessionRestored,
                    handler: appStateRefreshCoordinator
                )
                let snapshot = try await sessionStore.snapshot()
                guard self.initialStateLoadGeneration == generation else { return }
                await self.ensureLastLoginMethodLoaded(using: sessionStore)
                await self.applySession(snapshot, activateMessageBus: false)
            case .networkErrorPreserveState, .sessionExpired, .notLoggedIn:
                FireCfClearanceRefreshService.shared.setLoginStateConfirmed(false)
                let snapshot = try await sessionStore.snapshot()
                guard self.initialStateLoadGeneration == generation else { return }
                await self.applySession(snapshot, activateMessageBus: false)
            @unknown default:
                break
            }
        } catch {
            guard self.initialStateLoadGeneration == generation else { return }
            if await self.handleRecoverableSessionErrorIfNeeded(error) {
                return
            }
            if let sessionStore = self.sessionStore,
               let snapshot = try? await sessionStore.snapshot() {
                await self.applySession(snapshot, activateMessageBus: false)
            }
            self.errorMessage = error.localizedDescription
        }
    }

    func completeStartupAfterPreheatFailure(message: String?) {
        initialStateLoadGeneration &+= 1
        initialStateTask?.cancel()
        initialStateTask = nil
        initialStateLoadingDelayTask?.cancel()
        initialStateLoadingDelayTask = nil
        isBootstrappingSession = false
        isStartupLoadingVisible = false
        FireCfClearanceRefreshService.shared.setLoginStateConfirmed(false)
        if let message, !message.isEmpty {
            errorMessage = message
        }
    }

    func performStartupValidation() async {
        guard !isStartupValidationComplete else { return }
        guard !isStartupValidationInFlight else { return }
        isStartupValidationInFlight = true
        defer {
            isStartupValidationInFlight = false
            isStartupValidationComplete = true
        }

        do {
            let sessionStore = try await sessionStoreValue()
            _ = try await sessionStore.prepareStartupSession()
            do {
                _ = try await sessionStore.awaitPreloadedData()
            } catch {
                let snapshot = try? await sessionStore.snapshot()
                let readiness = snapshot?.readiness
                guard readiness?.canReadAuthenticatedApi == true
                    || readiness?.hasLoginCookie == true
                else {
                    throw error
                }
            }
            await completeStartupAfterPreheat()
        } catch {
            completeStartupAfterPreheatFailure(message: "网络异常，请重新登录")
        }
    }

    func prepareLoginForm() async {
        do {
            let sessionStore = try await sessionStoreValue()
            savedLoginCredential = try await sessionStore.loadSavedCredential()
            lastLoginMethod = try await sessionStore.loadLastLoginMethod()
            _ = try await loginCoordinatorValue()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func ensureLastLoginMethodLoaded(using sessionStore: FireSessionStore) async {
        guard lastLoginMethod == nil else { return }
        lastLoginMethod = try? await sessionStore.loadLastLoginMethod()
    }

    private func finishInitialStateLoading(generation: UInt64) {
        guard initialStateLoadGeneration == generation else {
            return
        }

        initialStateLoadingDelayTask?.cancel()
        initialStateLoadingDelayTask = nil
        isBootstrappingSession = false
        isStartupLoadingVisible = false
        initialStateTask = nil
    }
}
