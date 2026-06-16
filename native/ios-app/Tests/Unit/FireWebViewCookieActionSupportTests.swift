import Foundation
import XCTest
@testable import Fire

final class FireWebViewCookieActionSupportTests: XCTestCase {
    func testSetCookieHeaderParsesForWebKitStoreWrites() throws {
        let cookies = try FireWebViewCookieActionSupport.cookies(
            fromSetCookieHeader: "_t=token; Path=/; Domain=linux.do; Secure; HttpOnly",
            urlString: "https://linux.do/"
        )

        XCTAssertEqual(cookies.count, 1)
        XCTAssertEqual(cookies[0].name, "_t")
        XCTAssertEqual(cookies[0].value, "token")
        XCTAssertTrue(cookies[0].domain == "linux.do" || cookies[0].domain == ".linux.do")
        XCTAssertEqual(cookies[0].path, "/")
        XCTAssertTrue(cookies[0].isSecure)
        XCTAssertTrue(cookies[0].isHTTPOnly)
    }

    func testWebViewCookieInfoPreservesVisibleMetadata() throws {
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "linux.do",
            .path: "/",
            .name: "cf_clearance",
            .value: "clear",
            .secure: "TRUE",
            HTTPCookiePropertyKey("SameSite"): "None",
        ]))

        let info = FireWebViewCookieActionSupport.webViewCookieInfo(cookie)

        XCTAssertEqual(info.name, "cf_clearance")
        XCTAssertEqual(info.value, "clear")
        XCTAssertEqual(info.domain, "linux.do")
        XCTAssertEqual(info.path, "/")
        XCTAssertEqual(info.hostOnly, true)
        XCTAssertEqual(info.secure, true)
        XCTAssertEqual(info.sameSite, CookieSameSiteState.none)
    }

    func testDeleteMatchingUsesDomainAndPath() throws {
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .domain: ".linux.do",
            .path: "/session",
            .name: "_forum_session",
            .value: "session",
        ]))
        let url = try XCTUnwrap(URL(string: "https://linux.do/session/current"))

        XCTAssertTrue(
            FireWebViewCookieActionSupport.matchesExactDelete(
                cookie,
                url: url,
                name: "_forum_session",
                domain: ".linux.do",
                path: "/session"
            )
        )
        XCTAssertFalse(
            FireWebViewCookieActionSupport.matchesExactDelete(
                cookie,
                url: url,
                name: "_forum_session",
                domain: ".linux.do",
                path: "/other"
            )
        )
        XCTAssertTrue(
            FireWebViewCookieActionSupport.matchesDeleteByName(
                cookie,
                url: url,
                name: "_forum_session"
            )
        )
    }
}
