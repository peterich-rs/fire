import Foundation
import XCTest
@testable import Fire

@MainActor
final class FireCloudflareChallengeRecoveryTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        // Process-wide static gate: always start clean so parallel/prior suites
        // cannot leave `inFlight` true and hang subsequent cases.
        FireCloudflareChallengePresentationGate.resetForTesting()
    }

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
        // Pure Swift concurrency handshake — avoid XCTestExpectation + MainActor
        // Task races that flake on CI (~5s fulfillment timeout).
        let handshake = PresentationGateTestHandshake()
        var bodyCount = 0

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
                    handshake.signalBodyStarted {
                        continuation.resume()
                    }
                }
                return success
            }
        }

        await handshake.waitUntilBodyStarted()
        XCTAssertTrue(FireCloudflareChallengePresentationGate.isPresentationInFlight)

        let joinerTask = Task { @MainActor in
            await FireCloudflareChallengePresentationGate.runExclusive {
                bodyCount += 1
                return FireCloudflareChallengeCoordinator.softFailureResult(userCancelled: true)
            }
        }

        // Let the joiner attach to `joiners` before the owner finishes.
        await Task.yield()
        await Task.yield()
        handshake.resumeBody()

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

/// MainActor-isolated handshake for presentation-gate tests.
///
/// XCTestExpectation + `Task { @MainActor }` can miss each other under CI load
/// when the test method is already on MainActor; checked continuations resume
/// as soon as the body actually runs.
@MainActor
private final class PresentationGateTestHandshake {
    private var bodyStarted = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var resumeBodyImpl: (() -> Void)?

    func waitUntilBodyStarted() async {
        if bodyStarted { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if bodyStarted {
                continuation.resume()
            } else {
                waiters.append(continuation)
            }
        }
    }

    func signalBodyStarted(resumeBody: @escaping () -> Void) {
        resumeBodyImpl = resumeBody
        bodyStarted = true
        let pending = waiters
        waiters = []
        for waiter in pending {
            waiter.resume()
        }
    }

    func resumeBody() {
        let resume = resumeBodyImpl
        resumeBodyImpl = nil
        resume?()
    }
}
