import WebKit
import XCTest
@testable import Fire

final class FireLoginScriptsTests: XCTestCase {
    func testMinimalLoginHTMLUsesWebViewOwnedLoginEndpoints() {
        let html = FireLoginScripts.minimalLoginHTML(hcaptchaSiteKey: "site-key")

        XCTAssertTrue(html.contains("https://js.hcaptcha.com/1/api.js"))
        XCTAssertTrue(FireLoginScripts.linuxDoHcaptchaSiteKey.range(
            of: #"^[0-9a-f-]{36}$"#,
            options: .regularExpression
        ) != nil)
        XCTAssertTrue(html.contains("hcaptcha.render('hcaptcha'"))
        XCTAssertTrue(html.contains("window.__fireLogin = async function"))
        XCTAssertTrue(html.contains("fetch('/session/csrf'"))
        XCTAssertTrue(html.contains(#""\/captcha\/hcaptcha\/create.json""#))
        XCTAssertTrue(html.contains(#""\/hcaptcha\/create.json""#))
        XCTAssertTrue(html.contains("fetch('/session.json'"))
        XCTAssertTrue(html.contains("'X-Requested-With': 'XMLHttpRequest'"))
        XCTAssertTrue(html.contains("credentials: 'include'"))
        XCTAssertTrue(html.contains(FireLoginScripts.loginResultMessageName))
        XCTAssertTrue(html.contains(FireLoginScripts.hcaptchaReadyMessageName))
        XCTAssertTrue(html.contains(FireLoginScripts.hcaptchaContentHeightMessageName))
        XCTAssertTrue(html.contains("measureContentHeight"))
        XCTAssertTrue(html.contains("ResizeObserver"))
        XCTAssertTrue(html.contains("'rendered'"))
        XCTAssertFalse(html.contains("/login\""))
    }

    func testFireLoginInvocationJsonEscapesArguments() {
        let script = FireLoginScripts.fireLoginInvocation(
            identifier: "alice@example.com",
            password: #"p"ass\word"#,
            hcaptchaToken: "hc-token",
            secondFactorToken: nil
        )

        // Invocation must not return the async Promise directly to WKWebView.
        XCTAssertTrue(script.contains("window.__fireLogin("), script)
        XCTAssertTrue(script.contains("return true;"), script)
        XCTAssertTrue(script.contains("alice@example.com"), script)
        XCTAssertTrue(script.contains("hc-token"), script)
        XCTAssertTrue(script.contains("null"), script)
        // Promise must be detached, not returned as the evaluateJavaScript result.
        XCTAssertTrue(script.contains("typeof p.then"), script)
    }

    func testBenignEvaluateJavaScriptErrorDetectsUnsupportedPromiseType() {
        let unsupported = NSError(
            domain: "WKErrorDomain",
            code: 5,
            userInfo: [NSLocalizedDescriptionKey: "JavaScript execution returned a result of an unsupported type"]
        )
        XCTAssertTrue(FireLoginScripts.isBenignEvaluateJavaScriptError(unsupported))

        let messageOnly = NSError(
            domain: "AnyDomain",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "JavaScript execution returned a result of an unsupported type"]
        )
        XCTAssertTrue(FireLoginScripts.isBenignEvaluateJavaScriptError(messageOnly))

        let realError = NSError(
            domain: "WKErrorDomain",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "JavaScript exception occurred"]
        )
        XCTAssertFalse(FireLoginScripts.isBenignEvaluateJavaScriptError(realError))
    }

    func testMinimalLoginHTMLAllowsConfiguredHcaptchaEndpointFirst() {
        let html = FireLoginScripts.minimalLoginHTML(
            hcaptchaSiteKey: "site-key",
            hcaptchaCreateEndpoint: "/custom/hcaptcha/create.json"
        )

        XCTAssertLessThan(
            html.range(of: #""\/custom\/hcaptcha\/create.json""#)?.lowerBound ?? html.endIndex,
            html.range(of: #""\/captcha\/hcaptcha\/create.json""#)?.lowerBound ?? html.endIndex
        )
    }

    func testExternalLoginAutoStartScriptTargetsDiscourseButtons() {
        let google = FireExternalLoginScripts.autoStart(.google)
        XCTAssertTrue(google.contains("google_oauth2"), google)
        XCTAssertTrue(google.contains("button.btn-social."), google)
        XCTAssertTrue(google.contains("btn.click()"), google)

        let passkey = FireExternalLoginScripts.autoStart(.passkey)
        XCTAssertTrue(passkey.contains("passkey-login-button"), passkey)
        XCTAssertTrue(passkey.contains("btn.click()"), passkey)

        XCTAssertEqual(FireExternalLoginMethod.x.discourseProviderName, "twitter")
        XCTAssertEqual(FireExternalLoginMethod.apple.discourseProviderName, "apple")
        XCTAssertNil(FireExternalLoginMethod.passkey.discourseProviderName)
    }

    func testLastLoginMethodRoundTripsAndMapsExternalEntries() throws {
        let encoded = try JSONEncoder().encode(FireLastLoginMethod.github)
        let decoded = try JSONDecoder().decode(FireLastLoginMethod.self, from: encoded)
        XCTAssertEqual(decoded, .github)

        // Password is a first-class persisted login method.
        XCTAssertEqual(FireLastLoginMethod.password.rawValue, "password")
        XCTAssertEqual(FireLastLoginMethod.password.displayName, "账号密码")

        // External icon row only covers third-party entries.
        XCTAssertEqual(FireExternalLoginMethod.github.lastLoginMethod, .github)
        XCTAssertEqual(FireExternalLoginMethod.externalIcon(for: .discord), .discord)
        XCTAssertNil(FireExternalLoginMethod.externalIcon(for: .password))

        // Official brand assets live in the asset catalog.
        for method in FireExternalLoginMethod.allCases {
            XCTAssertNotNil(
                UIImage(named: method.assetName),
                "missing login provider asset \(method.assetName)"
            )
        }
    }

    func testColdStartAutoLoginEligibilityForPasswordAndGoogle() {
        let credential = FireSavedCredential(username: "alice", password: "secret")
        XCTAssertNotNil(credential)

        XCTAssertEqual(
            FireAutoLoginPlanner.coldStartKind(
                entry: .coldStart,
                lastLoginMethod: .password,
                savedCredential: credential
            ),
            .password(credential!)
        )
        XCTAssertNil(
            FireAutoLoginPlanner.coldStartKind(
                entry: .coldStart,
                lastLoginMethod: .password,
                savedCredential: nil
            )
        )

        // Explicit logout must never auto-login even with saved password credentials.
        XCTAssertNil(
            FireAutoLoginPlanner.coldStartKind(
                entry: .signedOut,
                lastLoginMethod: .password,
                savedCredential: credential
            )
        )
        XCTAssertNil(
            FireAutoLoginPlanner.coldStartKind(
                entry: .signedOut,
                lastLoginMethod: .google,
                savedCredential: nil
            )
        )

        // Google is in the headless external pool.
        XCTAssertEqual(
            FireAutoLoginPlanner.coldStartKind(
                entry: .coldStart,
                lastLoginMethod: .google,
                savedCredential: nil
            ),
            .external(.google)
        )
        XCTAssertTrue(FireAutoLoginPlanner.supportsHeadlessExternal(.google))

        // Other providers stay out until explicitly added to the pool.
        XCTAssertNil(
            FireAutoLoginPlanner.coldStartKind(
                entry: .coldStart,
                lastLoginMethod: .github,
                savedCredential: credential
            )
        )
        XCTAssertEqual(
            FireAutoLoginPlanner.loadingMessage(for: .password(credential!)),
            "正在准备安全验证…"
        )
        XCTAssertEqual(
            FireAutoLoginPlanner.loadingMessage(for: .external(.google)),
            "正在通过 Google 登录…"
        )
    }
}
