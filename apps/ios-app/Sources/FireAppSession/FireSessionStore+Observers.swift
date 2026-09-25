import Foundation

extension FireSessionStore {
    public func registerStateObserver(_ observer: any StateObserver) {
        core.registerStateObserver(observer: observer)
    }

    public func unregisterStateObserver() {
        core.unregisterStateObserver()
    }

    public func registerCloudflareChallengeHandler(
        _ handler: any CloudflareChallengeHandler
    ) throws {
        try core.session().registerCloudflareChallengeHandler(handler: handler)
    }

    public func unregisterCloudflareChallengeHandler() throws {
        try core.session().unregisterCloudflareChallengeHandler()
    }

    public func registerCloudflareClearanceResolvedHandler(
        _ handler: any CloudflareClearanceResolvedHandler
    ) throws {
        try core.session().registerCloudflareClearanceResolvedHandler(handler: handler)
    }

    public func unregisterCloudflareClearanceResolvedHandler() throws {
        try core.session().unregisterCloudflareClearanceResolvedHandler()
    }

    public func cloudflareClearanceResolvedGeneration() throws -> UInt64 {
        try core.session().cloudflareClearanceResolvedGeneration()
    }

    public func registerCookieSelfHealingHandler(
        _ handler: any CookieSelfHealingHandler
    ) throws {
        try core.session().registerCookieSelfHealingHandler(handler: handler)
    }

    public func unregisterCookieSelfHealingHandler() throws {
        try core.session().unregisterCookieSelfHealingHandler()
    }
}
