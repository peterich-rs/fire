import Foundation

@MainActor
final class FireTopicTimingTracker {
    typealias Reporter = (_ topicId: UInt64, _ topicTimeMs: UInt32, _ timings: [UInt32: UInt32]) async -> Bool

    private enum Constants {
        static let tickInterval: Duration = .seconds(1)
        static let flushInterval: TimeInterval = 30
        static let idlePauseInterval: TimeInterval = 180
        static let maxTrackedPostMilliseconds = 6 * 60 * 1_000
    }

    private let topicId: UInt64

    private var reporter: Reporter?
    private var tickTask: Task<Void, Never>?
    private var lastTickAt = Date()
    private var lastInteractionAt = Date()
    private var lastFlushAt = Date()
    private var visiblePostNumbers: Set<UInt32> = []
    private var pendingTimings: [UInt32: Int] = [:]
    private var totalTimings: [UInt32: Int] = [:]
    private var topicTimeMs = 0
    private var isSceneActive = true
    private var isRunning = false

    init(topicId: UInt64) {
        self.topicId = topicId
    }

    func start(reporter: @escaping Reporter) {
        guard !isRunning else { return }

        self.reporter = reporter
        isRunning = true
        let now = Date()
        lastTickAt = now
        lastInteractionAt = now
        lastFlushAt = now

        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: Constants.tickInterval)
                } catch {
                    return
                }
                guard let self else { return }
                await self.tick()
            }
        }
    }

    func stop() async {
        guard isRunning else { return }

        tickTask?.cancel()
        tickTask = nil

        await tick()
        await flushIfNeeded()

        isRunning = false
        reporter = nil
        visiblePostNumbers.removeAll()
    }

    func updateVisiblePostNumbers(_ postNumbers: Set<UInt32>) {
        guard visiblePostNumbers != postNumbers else { return }
        visiblePostNumbers = postNumbers
        recordInteraction()
    }

    func recordInteraction() {
        lastInteractionAt = Date()
    }

    func setSceneActive(_ isActive: Bool) async {
        guard isSceneActive != isActive else { return }

        isSceneActive = isActive
        lastTickAt = Date()
        if isActive {
            lastInteractionAt = lastTickAt
        } else {
            await flushIfNeeded()
        }
    }

    private func tick() async {
        guard isRunning else { return }

        let now = Date()
        let diffMs = max(Int(now.timeIntervalSince(lastTickAt) * 1_000), 0)
        lastTickAt = now

        guard diffMs > 0 else { return }
        guard isSceneActive else { return }
        guard now.timeIntervalSince(lastInteractionAt) <= Constants.idlePauseInterval else { return }

        topicTimeMs = topicTimeMs.saturatingAdd(diffMs)
        for postNumber in visiblePostNumbers {
            let total = totalTimings[postNumber] ?? 0
            let remaining = Constants.maxTrackedPostMilliseconds - total
            guard remaining > 0 else { continue }

            let trackedMs = min(diffMs, remaining)
            pendingTimings[postNumber] = (pendingTimings[postNumber] ?? 0).saturatingAdd(trackedMs)
            totalTimings[postNumber] = total.saturatingAdd(trackedMs)
        }

        if now.timeIntervalSince(lastFlushAt) >= Constants.flushInterval {
            await flushIfNeeded()
        }
    }

    private func flushIfNeeded() async {
        lastFlushAt = Date()

        guard let reporter else { return }
        guard topicTimeMs > 0 else { return }

        let normalizedTimings = pendingTimings.reduce(into: [UInt32: UInt32]()) { partialResult, entry in
            guard entry.value > 0 else { return }
            partialResult[entry.key] = Self.normalizeMilliseconds(entry.value)
        }
        guard !normalizedTimings.isEmpty else { return }

        let normalizedTopicTimeMs = Self.normalizeMilliseconds(topicTimeMs)
        guard normalizedTopicTimeMs > 0 else { return }

        let didReport = await reporter(topicId, normalizedTopicTimeMs, normalizedTimings)
        guard didReport else { return }

        topicTimeMs = 0
        pendingTimings = [:]
    }

    private static func normalizeMilliseconds(_ value: Int) -> UInt32 {
        guard value > 0 else { return 0 }
        return UInt32(min(value, Int(UInt32.max)))
    }
}

private extension Int {
    func saturatingAdd(_ other: Int) -> Int {
        let (result, overflow) = addingReportingOverflow(other)
        return overflow ? .max : result
    }
}
