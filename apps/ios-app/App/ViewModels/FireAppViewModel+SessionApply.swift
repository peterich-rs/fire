import Foundation
import UIKit
import WebKit

extension FireAppViewModel {
    func refreshBootstrap() {
        Task {
            do {
                try await FireAPMManager.shared.withSpan(.bootstrapRefresh) {
                    let sessionStore = try await sessionStoreValue()
                    errorMessage = nil
                    await applySession(try await sessionStore.refreshBootstrap())
                    await refreshHomeFeedIfPossible(force: false)
                }
            } catch {
                if await handleRecoverableSessionErrorIfNeeded(error) {
                    return
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    func clearTopicState() {
        homeFeedStore?.reset(resetTopicKind: true)
        topicDetailStore?.reset()
    }

    func applySession(_ session: SessionState, activateMessageBus: Bool = true) async {
        let wasAuthenticated = self.session.readiness.canReadAuthenticatedApi
        let shouldSyncNativeCookies = session.cookies != self.session.cookies
            || session.bootstrap.baseUrl != self.session.bootstrap.baseUrl
        self.session = session
        if shouldSyncNativeCookies {
            session.syncCookiesToNativeStorage()
        }
        homeFeedStore?.applySession(session)
        topicDetailStore?.applySession(session)
        if let request = session.readPathLoginRequest,
           request.generation != lastReadPathLoginGeneration {
            lastReadPathLoginGeneration = request.generation
            let operation = request.operation
            let recovered = await attemptHostCookieResyncRecovery(operation: operation)
            let succeeded: Bool
            if recovered {
                succeeded = true
            } else {
                succeeded = await attemptMidSessionHeadlessReauth(operation: operation)
            }
            if let sessionStore = currentSessionStore() {
                try? await sessionStore.completeReadPathLogin(
                    generation: request.generation,
                    succeeded: succeeded
                )
            }
        }

        let isAuthenticated = session.readiness.canReadAuthenticatedApi
        if wasAuthenticated && !isAuthenticated {
            if let coordinator = try? await loginCoordinatorValue() {
                try? await coordinator.clearSameSiteIdentityCookies(preservingCfClearance: true)
            }
            if serverForcedLogout {
                serverForcedLogout = false
            } else if !didRequestExplicitLogout {
                // Raise the reauth hold synchronously so RootCoordinator's next main-runloop
                // auth sink keeps the main shell mounted for Google headless recovery.
                scheduleMidSessionReauthAfterPassiveDeauth()
            }
        }

        if isAuthenticated {
            await notificationStore?.syncStateFromRuntimeIfAvailable()
            if needsBootstrapIdentityHydration(session) {
                Task { await self.hydrateBootstrapIfNeeded() }
            }
        } else {
            notificationStore?.reset()
            updateWidgetData()
        }

        // Reconcile MessageBus lifecycle
        if session.readiness.canOpenMessageBus && activateMessageBus && !isMessageBusActive {
            await startMessageBus()
        } else if !session.readiness.canOpenMessageBus && isMessageBusActive {
            stopMessageBus()
        } else if !session.readiness.canOpenMessageBus {
            stopMessageBus()
        }

        if let coordinator = try? await loginCoordinatorValue() {
            FireCfClearanceRefreshService.shared.updateSession(
                session,
                loginCoordinator: coordinator,
                onSessionRefreshed: { [weak self] updatedSession in
                    guard let self else { return }
                    await self.cfClearanceDidRefresh(updatedSession)
                }
            )
        }
    }

    func cfClearanceDidRefresh(_ updatedSession: SessionState) async {
        await applySession(updatedSession)
    }

    func handleAppStateRefreshEvent(_ event: AppStateRefreshEventState) {
        if event.trigger == .cloudflareResolved {
            Task { @MainActor in
                self.homeFeedStore?.clearTopicLoadError()
                if self.session.readiness.canOpenMessageBus {
                    await self.restartMessageBusAfterClearanceIfPossible()
                }
            }
        }
    }

    func handleClearanceResolved(_ event: CloudflareClearanceResolvedEventState) async {
        homeFeedStore?.clearTopicLoadError()
        FireAPMManager.shared.recordBreadcrumb(
            level: "info",
            target: "auth.cf",
            message: "clearance resolved gen=\(event.generation) login=\(event.hasLoginSession) bus=\(event.canOpenMessageBus)"
        )
        if event.canOpenMessageBus || session.readiness.canOpenMessageBus {
            await restartMessageBusAfterClearanceIfPossible()
        }
        // Home topic list may still show a CF failure banner; force one refresh.
        _ = await refreshHomeFeedIfPossible(force: true)
        await hydrateBootstrapIfNeeded(force: true)
    }

    /// Pull home bootstrap when cookies exist but `current_username` / preloaded
    /// data never landed. Profile, logout, and MessageBus all need that identity.
    func hydrateBootstrapIfNeeded(force: Bool = false) async {
        let current = session
        guard current.hasLoginSession || current.readiness.canReadAuthenticatedApi else {
            lastBootstrapHydrationAttemptKey = nil
            return
        }
        guard needsBootstrapIdentityHydration(current) else {
            lastBootstrapHydrationAttemptKey = nil
            return
        }
        let attemptKey = bootstrapHydrationAttemptKey(current)
        guard force || lastBootstrapHydrationAttemptKey != attemptKey else {
            return
        }
        guard !isHydratingBootstrap else {
            return
        }
        isHydratingBootstrap = true
        lastBootstrapHydrationAttemptKey = attemptKey
        defer { isHydratingBootstrap = false }
        do {
            let sessionStore = try await sessionStoreValue()
            var snapshot = try await sessionStore.refreshBootstrapIfNeeded()
            await applySession(snapshot, activateMessageBus: false)
            if needsBootstrapIdentityHydration(snapshot) {
                snapshot = try await sessionStore.refreshBootstrap()
                await applySession(snapshot, activateMessageBus: false)
            }
        } catch {
            FireAPMManager.shared.recordBreadcrumb(
                level: "warn",
                target: "auth.bootstrap",
                message: "bootstrap hydration failed: \(error.localizedDescription)"
            )
        }
    }

    private func needsBootstrapIdentityHydration(_ session: SessionState) -> Bool {
        !session.readiness.hasCurrentUser || !session.readiness.hasPreloadedData
    }

    private func bootstrapHydrationAttemptKey(_ session: SessionState) -> String {
        [
            session.hasLoginSession ? "1" : "0",
            session.readiness.canReadAuthenticatedApi ? "1" : "0",
            session.cookies.tToken ?? "",
            session.cookies.forumSession ?? "",
        ].joined(separator: "|")
    }

    func syncSessionSnapshotIfAvailable(from sessionStore: FireSessionStore) async {
        if let snapshot = try? await sessionStore.snapshot() {
            await applySession(snapshot)
        }
    }

    func registerStateObserver(with sessionStore: FireSessionStore) async {
        await sessionStore.registerStateObserver(stateObserverCoordinator)
    }
}
