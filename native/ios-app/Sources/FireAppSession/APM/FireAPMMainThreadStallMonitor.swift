import Foundation
import QuartzCore

final class FireAPMMainThreadStallMonitor {
    private enum Constants {
        static let heartbeatInterval: TimeInterval = 0.25
        static let stallThresholdMs: Double = 500
        static let severeThresholdMs: Double = 2_000
    }

    private let monitorQueue = DispatchQueue(label: "com.fire.apm.main-thread-stall", qos: .utility)
    private let onStall: @Sendable (_ durationMs: UInt64, _ severe: Bool) -> Void
    private var monitorTimer: DispatchSourceTimer?
    private var heartbeatScheduled = false
    private var isSceneActive = true
    private var lastHeartbeat = CACurrentMediaTime()
    private var emittedStall = false
    private var emittedSevere = false

    init(onStall: @escaping @Sendable (_ durationMs: UInt64, _ severe: Bool) -> Void) {
        self.onStall = onStall
    }

    func start() {
        guard monitorTimer == nil else { return }
        lastHeartbeat = CACurrentMediaTime()
        scheduleHeartbeat()

        let timer = DispatchSource.makeTimerSource(queue: monitorQueue)
        timer.schedule(deadline: .now() + Constants.heartbeatInterval, repeating: Constants.heartbeatInterval)
        timer.setEventHandler { [weak self] in
            self?.checkForStall()
        }
        monitorTimer = timer
        timer.resume()
    }

    func stop() {
        monitorTimer?.cancel()
        monitorTimer = nil
        heartbeatScheduled = false
    }

    func setSceneActive(_ active: Bool) {
        monitorQueue.async {
            self.isSceneActive = active
            if active {
                self.lastHeartbeat = CACurrentMediaTime()
                self.emittedStall = false
                self.emittedSevere = false
            }
        }
    }

    private func scheduleHeartbeat() {
        guard !heartbeatScheduled else { return }
        heartbeatScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.heartbeatInterval) { [weak self] in
            guard let self else { return }
            self.monitorQueue.async {
                self.lastHeartbeat = CACurrentMediaTime()
                self.heartbeatScheduled = false
                self.scheduleHeartbeat()
            }
        }
    }

    private func checkForStall() {
        guard isSceneActive else { return }

        let deltaMs = max((CACurrentMediaTime() - lastHeartbeat) * 1_000, 0)
        if deltaMs >= Constants.stallThresholdMs {
            let severe = deltaMs >= Constants.severeThresholdMs
            if !emittedStall || (severe && !emittedSevere) {
                onStall(UInt64(deltaMs.rounded()), severe)
                emittedStall = true
                if severe {
                    emittedSevere = true
                }
            }
        } else {
            emittedStall = false
            emittedSevere = false
        }
    }
}
