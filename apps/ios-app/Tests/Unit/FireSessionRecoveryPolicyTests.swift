import XCTest
@testable import Fire

final class FireSessionRecoveryPolicyTests: XCTestCase {
    func testCloudflareRecoverySuppressesPassiveLogoutAndBrowserPrompt() {
        XCTAssertTrue(FireSessionRecoveryPolicy.suppressesHostLoginRecovery(.cloudflare))
        XCTAssertFalse(FireSessionRecoveryPolicy.suppressesHostLoginRecovery(.idle))
    }
}
