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
}
