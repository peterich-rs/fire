import XCTest
@testable import Fire

@MainActor
final class FireTopicTimingTrackerTests: XCTestCase {
    func testFailedReportBacksOffSubsequentFlushes() async throws {
        let tracker = FireTopicTimingTracker(topicId: 123)
        var reports: [(topicId: UInt64, topicTimeMs: UInt32, timings: [UInt32: UInt32])] = []

        tracker.start { topicId, topicTimeMs, timings in
            reports.append((topicId, topicTimeMs, timings))
            return false
        }
        tracker.updateVisiblePostNumbers([1])

        try await Task.sleep(for: .milliseconds(1_100))
        await tracker.setSceneActive(false)
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports.first?.topicId, 123)
        XCTAssertEqual(reports.first?.timings.keys.sorted(), [UInt32(1)])

        await tracker.setSceneActive(true)
        try await Task.sleep(for: .milliseconds(1_100))
        await tracker.setSceneActive(false)
        await tracker.stop()

        XCTAssertEqual(reports.count, 1)
    }

    func testSuccessfulReportClearsPendingTimings() async throws {
        let tracker = FireTopicTimingTracker(topicId: 456)
        var reports: [[UInt32: UInt32]] = []

        tracker.start { _, _, timings in
            reports.append(timings)
            return true
        }
        tracker.updateVisiblePostNumbers([2])

        try await Task.sleep(for: .milliseconds(1_100))
        await tracker.setSceneActive(false)
        await tracker.stop()

        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports.first?.keys.sorted(), [UInt32(2)])
    }
}
