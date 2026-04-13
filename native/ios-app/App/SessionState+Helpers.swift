import Foundation
import WebKit

@MainActor
protocol MirroredCookieStore {
    func getAllCookies() async -> [HTTPCookie]
    func setCookie(_ cookie: HTTPCookie) async
    func deleteCookie(_ cookie: HTTPCookie) async
}

@MainActor
final class WebKitMirroredCookieStore: MirroredCookieStore {
    private let store: WKHTTPCookieStore

    init(store: WKHTTPCookieStore) {
        self.store = store
    }

    func getAllCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    func setCookie(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { continuation in
            store.setCookie(cookie) {
                continuation.resume()
            }
        }
    }

    func deleteCookie(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { continuation in
            store.delete(cookie) {
                continuation.resume()
            }
        }
    }
}

@MainActor
enum MirroredCookieStoreFactory {
    static var makeWebKitStore: () -> any MirroredCookieStore = {
        WebKitMirroredCookieStore(store: WKWebsiteDataStore.default().httpCookieStore)
    }
}

extension SessionState {
    private static let scalarFallbackCookieNames: Set<String> = ["_t", "_forum_session", "cf_clearance"]

    static func placeholder(baseUrl: String = "https://linux.do") -> SessionState {
        SessionState(
            cookies: CookieState(
                tToken: nil,
                forumSession: nil,
                cfClearance: nil,
                csrfToken: nil,
                platformCookies: []
            ),
            bootstrap: BootstrapState(
                baseUrl: baseUrl,
                discourseBaseUri: nil,
                sharedSessionKey: nil,
                currentUsername: nil,
                currentUserId: nil,
                notificationChannelPosition: nil,
                longPollingBaseUrl: nil,
                turnstileSitekey: nil,
                topicTrackingStateMeta: nil,
                preloadedJson: nil,
                hasPreloadedData: false,
                hasSiteMetadata: false,
                topTags: [],
                canTagTopics: false,
                categories: [],
                hasSiteSettings: false,
                enabledReactionIds: ["heart"],
                minPostLength: 1,
                minTopicTitleLength: 15,
                minFirstPostLength: 20,
                minPersonalMessageTitleLength: 2,
                minPersonalMessagePostLength: 10,
                defaultComposerCategory: nil
            ),
            readiness: SessionReadinessState(
                hasLoginCookie: false,
                hasForumSession: false,
                hasCloudflareClearance: false,
                hasCsrfToken: false,
                hasCurrentUser: false,
                hasPreloadedData: false,
                hasSharedSessionKey: false,
                canReadAuthenticatedApi: false,
                canWriteAuthenticatedApi: false,
                canOpenMessageBus: false
            ),
            loginPhase: .anonymous,
            hasLoginSession: false,
            profileDisplayName: "未登录",
            loginPhaseLabel: "未登录"
        )
    }

    var profileStatusTitle: String {
        loginPhaseLabel
    }

    var baseURL: URL {
        URL(string: bootstrap.baseUrl) ?? URL(string: "https://linux.do")!
    }

    @MainActor
    func mirrorCookiesToNativeStorage() async {
        let host = baseURL.host ?? "linux.do"
        let batch = bridgedCookieBatch(host: host)

        mirrorCookiesToSharedStorage(batch.cookies, host: host, fullSameSiteScope: batch.usesFullSameSiteScope)
        await mirrorCookiesToWebKitStorage(
            batch.cookies,
            host: host,
            fullSameSiteScope: batch.usesFullSameSiteScope
        )
    }

    @MainActor
    private func mirrorCookiesToSharedStorage(
        _ cookies: [HTTPCookie],
        host: String,
        fullSameSiteScope: Bool
    ) {
        let cookieStorage = HTTPCookieStorage.shared

        for existingCookie in cookieStorage.cookies ?? [] {
            guard Self.shouldMirror(existingCookie, host: host, fullSameSiteScope: fullSameSiteScope) else {
                continue
            }
            cookieStorage.deleteCookie(existingCookie)
        }

        for cookie in cookies {
            cookieStorage.setCookie(cookie)
        }
    }

    @MainActor
    private func mirrorCookiesToWebKitStorage(
        _ cookies: [HTTPCookie],
        host: String,
        fullSameSiteScope: Bool
    ) async {
        let store = MirroredCookieStoreFactory.makeWebKitStore()
        let existingCookies = await currentWebKitMirroredCookies(
            host: host,
            fullSameSiteScope: fullSameSiteScope,
            from: store
        )
        if Self.cookieDescriptors(existingCookies) == Self.cookieDescriptors(cookies) {
            return
        }

        for existingCookie in existingCookies {
            await deleteCookie(existingCookie, from: store)
        }

        for cookie in cookies {
            await setCookie(cookie, in: store)
        }
    }

    @MainActor
    private func currentWebKitMirroredCookies(
        host: String,
        fullSameSiteScope: Bool,
        from store: any MirroredCookieStore
    ) async -> [HTTPCookie] {
        await store.getAllCookies().filter {
            Self.shouldMirror($0, host: host, fullSameSiteScope: fullSameSiteScope)
        }
    }

    private func bridgedCookieBatch(host: String) -> MirroredCookieBatch {
        let secure = baseURL.scheme?.lowercased() == "https"
        let platformCookies = cookies.platformCookies
            .filter { Self.shouldBridgePlatformCookie($0, host: host) }
            .compactMap { cookie in
                Self.makeCookie(
                    name: cookie.name,
                    value: cookie.value,
                    domain: cookie.domain ?? host,
                    path: cookie.path ?? "/",
                    expiresAtUnixMs: cookie.expiresAtUnixMs,
                    secure: secure,
                    originURL: baseURL
                )
            }
        let usesFullSameSiteScope = !platformCookies.isEmpty

        let mirroredNames = Set(platformCookies.map(\.name))
        let scalarFallbackCandidates: [(String, String?)] = [
            ("_t", cookies.tToken),
            ("_forum_session", cookies.forumSession),
            ("cf_clearance", cookies.cfClearance),
        ]
        let scalarFallback: [HTTPCookie] = scalarFallbackCandidates.compactMap {
            (name: String, value: String?) -> HTTPCookie? in
            guard !mirroredNames.contains(name), let value, !value.isEmpty else {
                return nil
            }

            return Self.makeCookie(
                name: name,
                value: value,
                domain: host,
                path: "/",
                expiresAtUnixMs: nil,
                secure: secure,
                originURL: baseURL
            )
        }

        let sortedCookies = (platformCookies + scalarFallback).sorted {
            let lhs = Self.cookieDescriptor($0)
            let rhs = Self.cookieDescriptor($1)
            return lhs < rhs
        }

        return MirroredCookieBatch(
            cookies: sortedCookies,
            usesFullSameSiteScope: usesFullSameSiteScope
        )
    }

    private static func shouldBridgePlatformCookie(
        _ cookie: PlatformCookieState,
        host: String
    ) -> Bool {
        let normalizedValue = cookie.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedValue.isEmpty else {
            return false
        }
        if let expiresAtUnixMs = cookie.expiresAtUnixMs, expiresAtUnixMs <= currentUnixMs() {
            return false
        }

        return sameSiteDomainMatches(cookie.domain ?? host, host: host)
    }

    private static func shouldMirror(
        _ cookie: HTTPCookie,
        host: String,
        fullSameSiteScope: Bool
    ) -> Bool {
        if !fullSameSiteScope && !scalarFallbackCookieNames.contains(cookie.name) {
            return false
        }

        return sameSiteDomainMatches(cookie.domain, host: host)
    }

    private static func sameSiteDomainMatches(_ domain: String, host: String) -> Bool {
        let normalizedHost = normalizeDomain(host)
        let normalizedDomain = normalizeDomain(domain)
        return normalizedDomain == normalizedHost
            || normalizedDomain.hasSuffix(".\(normalizedHost)")
    }

    private static func currentUnixMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private static func normalizeDomain(_ domain: String) -> String {
        let normalized = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix(".") {
            return String(normalized.dropFirst())
        }
        return normalized
    }

    private static func makeCookie(
        name: String,
        value: String,
        domain: String,
        path: String,
        expiresAtUnixMs: Int64?,
        secure: Bool,
        originURL: URL
    ) -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path,
            .originURL: originURL,
        ]
        if secure {
            properties[.secure] = true
        }
        if let expiresAtUnixMs {
            properties[.expires] = Date(timeIntervalSince1970: TimeInterval(expiresAtUnixMs) / 1000)
        }
        return HTTPCookie(properties: properties)
    }

    private static func cookieDescriptors(_ cookies: [HTTPCookie]) -> [String] {
        cookies.map(cookieDescriptor).sorted()
    }

    private static func cookieDescriptor(_ cookie: HTTPCookie) -> String {
        let expiry = cookie.expiresDate.map { Int64($0.timeIntervalSince1970 * 1000) }
            .map(String.init) ?? "session"
        return "\(cookie.name)|\(normalizeDomain(cookie.domain))|\(cookie.path)|\(cookie.value)|\(expiry)"
    }

    @MainActor
    private func setCookie(_ cookie: HTTPCookie, in store: any MirroredCookieStore) async {
        await store.setCookie(cookie)
    }

    @MainActor
    private func deleteCookie(_ cookie: HTTPCookie, from store: any MirroredCookieStore) async {
        await store.deleteCookie(cookie)
    }
}

private struct MirroredCookieBatch {
    let cookies: [HTTPCookie]
    let usesFullSameSiteScope: Bool
}

extension TopicListKindState {
    static let orderedCases: [TopicListKindState] = [
        .latest,
        .new,
        .unread,
        .unseen,
        .hot,
        .top,
    ]

    var title: String {
        switch self {
        case .latest:
            return "Latest"
        case .new:
            return "New"
        case .unread:
            return "Unread"
        case .unseen:
            return "Unseen"
        case .hot:
            return "Hot"
        case .top:
            return "Top"
        case .privateMessagesInbox:
            return "收件箱"
        case .privateMessagesSent:
            return "已发送"
        }
    }
}
