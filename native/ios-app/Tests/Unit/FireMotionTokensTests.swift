import XCTest
@testable import Fire

@MainActor
final class FireMotionTokensTests: XCTestCase {
    func testDurationsZeroOutUnderReduceMotion() {
        XCTAssertEqual(FireMotionTokens.duration(for: .tap, reduceMotion: true), 0)
        XCTAssertEqual(FireMotionTokens.duration(for: .standard, reduceMotion: true), 0)
        XCTAssertEqual(FireMotionTokens.duration(for: .navPush, reduceMotion: true), 0)
    }

    func testDurationsNonZeroAndConservativeWhenReduceMotionOff() {
        let tap = FireMotionTokens.duration(for: .tap, reduceMotion: false)
        let standard = FireMotionTokens.duration(for: .standard, reduceMotion: false)
        let navPush = FireMotionTokens.duration(for: .navPush, reduceMotion: false)

        XCTAssertGreaterThan(tap, 0)
        XCTAssertGreaterThan(standard, 0)
        XCTAssertGreaterThan(navPush, 0)
        // Spec: "Tokens stay conservative (≤ 250 ms)." Keep all three
        // durations at or under that ceiling.
        XCTAssertLessThanOrEqual(tap, 0.25)
        XCTAssertLessThanOrEqual(standard, 0.25)
        XCTAssertLessThanOrEqual(navPush, 0.25)
    }

    func testRespectingReduceMotionGuardSkipsBodyWhenSet() {
        var ran = false
        _ = fireRespectingReduceMotion(true) {
            ran = true
            return 1
        }
        XCTAssertFalse(ran, "body must not run when reduceMotion is true")
    }

    func testRespectingReduceMotionGuardRunsBodyWhenUnset() {
        var ran = false
        let result = fireRespectingReduceMotion(false) {
            ran = true
            return 42
        }
        XCTAssertTrue(ran)
        XCTAssertEqual(result, 42)
    }
}
