import Foundation

final class FireCookieSelfHealingRuntimeHandler: CookieSelfHealingHandler, @unchecked Sendable {
    private let loginCoordinator: FireWebViewLoginCoordinator

    init(loginCoordinator: FireWebViewLoginCoordinator) {
        self.loginCoordinator = loginCoordinator
    }

    nonisolated func healCookies(
        request: CookieSelfHealingRequestState
    ) -> CookieSelfHealingResultState {
        if Thread.isMainThread {
            return CookieSelfHealingResultState(
                completed: false,
                sessionEpoch: request.sessionEpoch
            )
        }

        let semaphore = DispatchSemaphore(value: 0)
        let result = LockedCookieSelfHealingResultState(
            CookieSelfHealingResultState(
                completed: false,
                sessionEpoch: request.sessionEpoch
            )
        )
        DispatchQueue.main.async { [loginCoordinator] in
            Task { @MainActor in
                do {
                    let targetURL = URL(string: request.targetUrl)
                    switch request.phase {
                    case .sweep:
                        _ = try await loginCoordinator.sweepCookies(
                            names: request.cookieNames,
                            targetURL: targetURL
                        )
                    case .nuclearReset:
                        try await loginCoordinator.nuclearResetCookies(
                            targetURL: targetURL
                        )
                    }
                    result.set(
                        CookieSelfHealingResultState(
                            completed: true,
                            sessionEpoch: request.sessionEpoch
                        )
                    )
                } catch {
                    result.set(
                        CookieSelfHealingResultState(
                            completed: false,
                            sessionEpoch: request.sessionEpoch
                        )
                    )
                }
                semaphore.signal()
            }
        }
        _ = semaphore.wait(timeout: .now() + 15)
        return result.get()
    }
}

private final class LockedCookieSelfHealingResultState: @unchecked Sendable {
    private let lock = NSLock()
    private var value: CookieSelfHealingResultState

    init(_ value: CookieSelfHealingResultState) {
        self.value = value
    }

    func set(_ value: CookieSelfHealingResultState) {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    func get() -> CookieSelfHealingResultState {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
