import Foundation
import Security

public enum FireAuthCookieSecureStoreError: Error {
    case encodeFailed(Error)
    case decodeFailed(Error)
    case invalidItemData
    case unexpectedStatus(OSStatus)
}

public struct FireStoredPlatformCookie: Codable, Equatable, Sendable {
    public var name: String
    public var value: String
    public var domain: String?
    public var path: String?

    public init(
        name: String,
        value: String,
        domain: String?,
        path: String?
    ) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
    }

    init(_ cookie: PlatformCookieState) {
        self.init(
            name: cookie.name,
            value: cookie.value,
            domain: cookie.domain,
            path: cookie.path
        )
    }

    func asPlatformCookie(baseURL: URL) -> PlatformCookieState {
        PlatformCookieState(
            name: name,
            value: value,
            domain: domain ?? baseURL.host ?? "linux.do",
            path: path ?? "/"
        )
    }
}

public protocol FireAuthCookieSecureStore: Sendable {
    func load() throws -> FireAuthCookieSecrets
    func save(_ secrets: FireAuthCookieSecrets) throws
    func clear(preserveCfClearance: Bool) throws
}

public struct FireAuthCookieSecrets: Codable, Equatable, Sendable {
    public var tToken: String?
    public var forumSession: String?
    public var cfClearance: String?
    public var platformCookies: [FireStoredPlatformCookie]

    public init(
        tToken: String? = nil,
        forumSession: String? = nil,
        cfClearance: String? = nil,
        platformCookies: [FireStoredPlatformCookie] = []
    ) {
        self.tToken = Self.normalized(tToken)
        self.forumSession = Self.normalized(forumSession)
        self.cfClearance = Self.normalized(cfClearance)
        self.platformCookies = Self.normalizedPlatformCookies(platformCookies)
    }

    public init(platformCookies: [PlatformCookieState]) {
        self.init(
            tToken: Self.latestNonEmptyValue(named: "_t", in: platformCookies),
            forumSession: Self.latestNonEmptyValue(named: "_forum_session", in: platformCookies),
            cfClearance: Self.latestNonEmptyValue(named: "cf_clearance", in: platformCookies),
            platformCookies: platformCookies.map(FireStoredPlatformCookie.init)
        )
    }

    public init(cookieState: CookieState) {
        if !cookieState.platformCookies.isEmpty {
            self.init(platformCookies: cookieState.platformCookies)
        } else {
            self.init(
                tToken: cookieState.tToken,
                forumSession: cookieState.forumSession,
                cfClearance: cookieState.cfClearance
            )
        }
    }

    public var isEmpty: Bool {
        tToken == nil && forumSession == nil && cfClearance == nil && platformCookies.isEmpty
    }

    public func preservingCfClearanceOnly() -> FireAuthCookieSecrets {
        FireAuthCookieSecrets(
            cfClearance: cfClearance,
            platformCookies: platformCookies.filter { storedCookie in
                let lowerName = storedCookie.name.lowercased()
                return lowerName != "_t" && lowerName != "_forum_session"
            }
        )
    }

    public func platformCookies(baseURL: URL) -> [PlatformCookieState] {
        if !platformCookies.isEmpty {
            return platformCookies.map { $0.asPlatformCookie(baseURL: baseURL) }
        }

        let host = baseURL.host ?? "linux.do"
        return [
            ("_t", tToken),
            ("_forum_session", forumSession),
            ("cf_clearance", cfClearance),
        ].compactMap { name, value in
            guard let value else {
                return nil
            }
            return PlatformCookieState(
                name: name,
                value: value,
                domain: host,
                path: "/"
            )
        }
    }

    private static func latestNonEmptyValue(
        named name: String,
        in cookies: [PlatformCookieState]
    ) -> String? {
        for cookie in cookies.reversed() where cookie.name == name {
            let normalized = normalized(cookie.value)
            if normalized != nil {
                return normalized
            }
        }
        return nil
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func normalizedPlatformCookies(
        _ cookies: [FireStoredPlatformCookie]
    ) -> [FireStoredPlatformCookie] {
        var deduped: [FireStoredPlatformCookie] = []
        for cookie in cookies {
            let normalizedCookie = FireStoredPlatformCookie(
                name: cookie.name,
                value: cookie.value,
                domain: Self.normalized(cookie.domain),
                path: Self.normalized(cookie.path) ?? "/"
            )
            let normalizedValue = normalizedCookie.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedCookie.name.isEmpty, !normalizedValue.isEmpty else {
                continue
            }
            deduped.removeAll { existing in
                existing.name == normalizedCookie.name
                    && existing.domain?.lowercased() == normalizedCookie.domain?.lowercased()
                    && (existing.path ?? "/") == (normalizedCookie.path ?? "/")
            }
            deduped.append(
                FireStoredPlatformCookie(
                    name: normalizedCookie.name,
                    value: normalizedValue,
                    domain: normalizedCookie.domain?.lowercased(),
                    path: normalizedCookie.path ?? "/"
                )
            )
        }
        return deduped
    }
}

public struct FireKeychainAuthCookieStore: FireAuthCookieSecureStore {
    public static let defaultService = "com.fire.app.ios.auth-cookies"

    private let service: String
    private let account: String

    public init(
        baseURL: URL,
        service: String = FireKeychainAuthCookieStore.defaultService
    ) {
        self.service = service
        self.account = baseURL.host?.lowercased() ?? baseURL.absoluteString.lowercased()
    }

    public func load() throws -> FireAuthCookieSecrets {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw FireAuthCookieSecureStoreError.invalidItemData
            }
            do {
                return try JSONDecoder().decode(FireAuthCookieSecrets.self, from: data)
            } catch {
                throw FireAuthCookieSecureStoreError.decodeFailed(error)
            }
        case errSecItemNotFound:
            return FireAuthCookieSecrets()
        default:
            throw FireAuthCookieSecureStoreError.unexpectedStatus(status)
        }
    }

    public func save(_ secrets: FireAuthCookieSecrets) throws {
        if secrets.isEmpty {
            try deleteItem()
            return
        }

        let data: Data
        do {
            data = try JSONEncoder().encode(secrets)
        } catch {
            throw FireAuthCookieSecureStoreError.encodeFailed(error)
        }

        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw FireAuthCookieSecureStoreError.unexpectedStatus(addStatus)
            }
        default:
            throw FireAuthCookieSecureStoreError.unexpectedStatus(updateStatus)
        }
    }

    public func clear(preserveCfClearance: Bool) throws {
        if preserveCfClearance {
            try save((try load()).preservingCfClearanceOnly())
        } else {
            try deleteItem()
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
    }

    private func deleteItem() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw FireAuthCookieSecureStoreError.unexpectedStatus(status)
        }
    }
}
