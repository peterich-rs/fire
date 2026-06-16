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
        XCTAssertFalse(html.contains("/login\""))
    }

    func testFireLoginInvocationJsonEscapesArguments() {
        let script = FireLoginScripts.fireLoginInvocation(
            identifier: "alice@example.com",
            password: #"p"ass\word"#,
            hcaptchaToken: "hc-token",
            secondFactorToken: nil
        )

        XCTAssertTrue(script.hasPrefix("window.__fireLogin("))
        XCTAssertTrue(script.contains(#""alice@example.com""#))
        XCTAssertTrue(script.contains(#""p\"ass\\word""#))
        XCTAssertTrue(script.contains(#""hc-token""#))
        XCTAssertTrue(script.hasSuffix(",null);"))
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
