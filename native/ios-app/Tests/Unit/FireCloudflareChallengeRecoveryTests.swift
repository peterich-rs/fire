import Foundation
import XCTest
@testable import Fire

@MainActor
final class FireCloudflareChallengeRecoveryTests: XCTestCase {
    override func tearDown() async throws {
        FireCloudflareChallengePresentationGate.resetForTesting()
        try await super.tearDown()
    }

    func testRecoveryActionWaitsOnlyForInProgress() {
        XCTAssertEqual(
            FireAppViewModel.cloudflareRecoveryAction(forReason: "in_progress"),
            .waitThenRetry
        )
        for reason in ["required", "failed", "cancelled", "cooldown", "background_suppressed", ""] {
            XCTAssertEqual(
                FireAppViewModel.cloudflareRecoveryAction(forReason: reason),
                .rethrow,
                "reason \(reason) must not auto-present or wait-retry"
            )
        }
    }

    func testIsCloudflareChallengeErrorStillRecognizesInProgress() {
        let error = FireUniFfiError.CloudflareChallenge(reason: "in_progress")
        XCTAssertTrue(FireAppViewModel.isCloudflareChallengeError(error))
        XCTAssertEqual(FireAppViewModel.cloudflareChallengeReason(from: error), "in_progress")
    }

    func testPresentationGateJoinsConcurrentCallersWithoutReentry() async {
        var bodyCount = 0
        var resumeOwner: (() -> Void)?
        let ownerStarted = expectation(description: "owner body started")

        let success = CloudflareChallengeResultState(
            completed: true,
            userCancelled: false,
            freshCfClearance: "joined-clearance",
            cookies: [],
            browserUserAgent: "TestAgent"
        )

        let ownerTask = Task { @MainActor in
            await FireCloudflareChallengePresentationGate.runExclusive {
                bodyCount += 1
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    resumeOwner = { continuation.resume() }
                    ownerStarted.fulfill()
                }
                return success
            }
        }

        await fulfillment(of: [ownerStarted], timeout: 5)
        XCTAssertTrue(FireCloudflareChallengePresentationGate.isPresentationInFlight)

        let joinerTask = Task { @MainActor in
            await FireCloudflareChallengePresentationGate.runExclusive {
                bodyCount += 1
                return FireCloudflareChallengeCoordinator.softFailureResult(userCancelled: true)
            }
        }

        // Allow the joiner to enter runExclusive and attach as a continuation joiner.
        await Task.yield()
        await Task.yield()
        resumeOwner?()

        let firstResult = await ownerTask.value
        let secondResult = await joinerTask.value

        XCTAssertEqual(bodyCount, 1, "joined callers must not re-enter present body")
        XCTAssertTrue(firstResult.completed)
        XCTAssertTrue(secondResult.completed)
        XCTAssertEqual(firstResult.freshCfClearance, "joined-clearance")
        XCTAssertEqual(secondResult.freshCfClearance, "joined-clearance")
        XCTAssertFalse(FireCloudflareChallengePresentationGate.isPresentationInFlight)
    }

    func testPresentationGateAllowsSequentialPresentations() async {
        var bodyCount = 0
        let first = await FireCloudflareChallengePresentationGate.runExclusive {
            bodyCount += 1
            return FireCloudflareChallengeCoordinator.softFailureResult(userCancelled: true)
        }
        let second = await FireCloudflareChallengePresentationGate.runExclusive {
            bodyCount += 1
            return CloudflareChallengeResultState(
                completed: true,
                userCancelled: false,
                freshCfClearance: "second",
                cookies: [],
                browserUserAgent: nil
            )
        }

        XCTAssertEqual(bodyCount, 2)
        XCTAssertTrue(first.userCancelled)
        XCTAssertTrue(second.completed)
        XCTAssertEqual(second.freshCfClearance, "second")
    }
}
