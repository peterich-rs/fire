import Foundation

public struct FireCapturedLoginState: Sendable, Equatable {
    public let currentURL: String?
    public let username: String?
    public let csrfToken: String?
    public let homeHTML: String?
    public let browserUserAgent: String?
    public let cookies: [PlatformCookieState]

    public init(
        currentURL: String?,
        username: String?,
        csrfToken: String?,
        homeHTML: String?,
        browserUserAgent: String?,
        cookies: [PlatformCookieState]
    ) {
        self.currentURL = currentURL
        self.username = username
        self.csrfToken = csrfToken
        self.homeHTML = homeHTML
        self.browserUserAgent = browserUserAgent
        self.cookies = cookies
    }
}
