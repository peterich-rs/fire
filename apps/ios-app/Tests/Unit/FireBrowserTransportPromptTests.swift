import XCTest
@testable import Fire

final class FireBrowserTransportPromptTests: XCTestCase {
    func testPresentsAskEnableOnceUntilSignalLeaves() {
        XCTAssertTrue(
            FireBrowserTransportPrompt.shouldPresent(
                kind: .askEnableBrowserTransport,
                alreadyLatched: false
            )
        )
        XCTAssertFalse(
            FireBrowserTransportPrompt.shouldPresent(
                kind: .askEnableBrowserTransport,
                alreadyLatched: true
            )
        )
        XCTAssertTrue(
            FireBrowserTransportPrompt.nextLatch(kind: .askEnableBrowserTransport)
        )
        XCTAssertFalse(
            FireBrowserTransportPrompt.nextLatch(kind: .cloudflareChallenge)
        )
        XCTAssertFalse(
            FireBrowserTransportPrompt.shouldPresent(kind: nil, alreadyLatched: false)
        )
    }
}
