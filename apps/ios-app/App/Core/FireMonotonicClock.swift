import Foundation

struct FireMonotonicInstant: Equatable, Comparable {
    var nanoseconds: UInt64

    func advanced(byNanoseconds interval: UInt64) -> FireMonotonicInstant {
        FireMonotonicInstant(nanoseconds: nanoseconds &+ interval)
    }

    func durationNanoseconds(to other: FireMonotonicInstant) -> UInt64 {
        other.nanoseconds &- nanoseconds
    }

    static func < (lhs: FireMonotonicInstant, rhs: FireMonotonicInstant) -> Bool {
        lhs.nanoseconds < rhs.nanoseconds
    }
}

enum FireMonotonicClock {
    static func now() -> FireMonotonicInstant {
        FireMonotonicInstant(nanoseconds: clock_gettime_nsec_np(CLOCK_UPTIME_RAW))
    }
}

func fireNanoseconds(seconds: Double) -> UInt64 {
    UInt64((seconds * 1_000_000_000).rounded())
}

func fireNanoseconds(milliseconds: Double) -> UInt64 {
    UInt64((milliseconds * 1_000_000).rounded())
}

func fireSleep(nanoseconds: UInt64) async throws {
    try await Task.sleep(nanoseconds: nanoseconds)
}
