import Foundation
import Security
import WebKit

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

final class FireSessionCandidateRuntimeHandler: SessionCandidateHandler, @unchecked Sendable {
    nonisolated func sessionCandidateCookies() -> SessionCandidateCookiesState {
        if Thread.isMainThread {
            return FireSessionCookieReader.candidateCookiesSync()
        }
        let box = LockedSessionCandidateCookiesState()
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            Task { @MainActor in
                box.set(await FireSessionCookieReader.candidateCookies())
                semaphore.signal()
            }
        }
        _ = semaphore.wait(timeout: .now() + 3)
        return box.get()
    }
}

enum FireSessionCookieReader {
    static func candidateCookiesSync() -> SessionCandidateCookiesState {
        SessionCandidateCookiesState(tToken: nil, forumSession: nil)
    }

    static func candidateCookies() async -> SessionCandidateCookiesState {
        let cookies = await platformCookies()
        return SessionCandidateCookiesState(
            tToken: cookies.last(where: { $0.name == "_t" && !$0.value.isEmpty })?.value,
            forumSession: cookies.last(where: { $0.name == "_forum_session" && !$0.value.isEmpty })?.value
        )
    }

    static func platformCookies() async -> [PlatformCookieState] {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                let mapped = cookies.compactMap { cookie -> PlatformCookieState? in
                    let value = cookie.value.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { return nil }
                    if let expires = cookie.expiresDate, expires <= Date() {
                        return nil
                    }
                    return PlatformCookieState(
                        name: cookie.name,
                        value: value,
                        domain: cookie.domain,
                        path: cookie.path,
                        expiresAtUnixMs: cookie.expiresDate.map { Int64($0.timeIntervalSince1970 * 1000) },
                        sameSite: nil
                    )
                }
                continuation.resume(returning: mapped)
            }
        }
    }
}

private final class LockedSessionCandidateCookiesState: @unchecked Sendable {
    private let lock = NSLock()
    private var value = SessionCandidateCookiesState(tToken: nil, forumSession: nil)

    func set(_ value: SessionCandidateCookiesState) {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    func get() -> SessionCandidateCookiesState {
        lock.lock()
        defer { lock.unlock() }
        return value
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

final class FireUserApiKeyCryptoRuntimeHandler: UserApiKeyCryptoHandler, @unchecked Sendable {
    private let defaults = UserDefaults.standard
    private let apiKeyName = "fire.user-api-key"
    private let tag = "com.fire.app.user-api-key"

    static func stableClientId() -> String {
        let key = "fire.user-api-key.client-id"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: key)
        return created
    }

    func publicKeyPem() -> String {
        guard let key = (try? existingPrivateKey()) ?? (try? generatePrivateKey()) else {
            return ""
        }
        guard let publicKey = SecKeyCopyPublicKey(key) else {
            return ""
        }
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            return ""
        }
        return Self.encodeSubjectPublicKeyInfo(data)
    }

    func decryptPayload(payload: String) -> String? {
        let normalized = payload.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        guard let cipher = Data(base64Encoded: normalized),
              let key = try? existingPrivateKey() else {
            return nil
        }
        var error: Unmanaged<CFError>?
        guard let plain = SecKeyCreateDecryptedData(
            key,
            .rsaEncryptionPKCS1,
            cipher as CFData,
            &error
        ) as Data? else {
            return nil
        }
        return String(data: plain, encoding: .utf8)
    }

    func readApiKey() -> String? {
        defaults.string(forKey: apiKeyName)
    }

    func writeApiKey(apiKey: String) {
        defaults.set(apiKey, forKey: apiKeyName)
    }

    func clearApiKey() {
        defaults.removeObject(forKey: apiKeyName)
    }

    private func existingPrivateKey() throws -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag.data(using: .utf8) as Any,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecReturnRef as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let item else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return (item as! SecKey)
    }

    private func generatePrivateKey() throws -> SecKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag.data(using: .utf8) as Any,
            ],
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw error!.takeRetainedValue()
        }
        return key
    }

    private static func encodeSubjectPublicKeyInfo(_ rsaPublicKey: Data) -> String {
        let algorithm: [UInt8] = [
            0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00,
        ]
        var bitString = Data([0x03])
        bitString.append(asn1Length(rsaPublicKey.count + 1))
        bitString.append(0x00)
        bitString.append(rsaPublicKey)
        var sequence = Data([0x30])
        let body = Data(algorithm) + bitString
        sequence.append(asn1Length(body.count))
        sequence.append(body)
        let base64 = sequence.base64EncodedString()
        var lines = ["-----BEGIN PUBLIC KEY-----"]
        var index = base64.startIndex
        while index < base64.endIndex {
            let end = base64.index(index, offsetBy: 64, limitedBy: base64.endIndex) ?? base64.endIndex
            lines.append(String(base64[index..<end]))
            index = end
        }
        lines.append("-----END PUBLIC KEY-----")
        return lines.joined(separator: "\n")
    }

    private static func asn1Length(_ length: Int) -> Data {
        if length < 0x80 {
            return Data([UInt8(length)])
        }
        if length < 0x100 {
            return Data([0x81, UInt8(length)])
        }
        return Data([0x82, UInt8(length >> 8), UInt8(length & 0xff)])
    }
}
