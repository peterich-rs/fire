import Foundation
import UIKit

#if canImport(Darwin)
import Darwin.Mach
#endif

final class FireAPMResourceSampler {
    private enum Constants {
        static let defaultInterval: TimeInterval = 5
        static let boostedInterval: TimeInterval = 1
        static let bootstrapBoostWindow: TimeInterval = 60
    }

    private let queue = DispatchQueue(label: "com.fire.apm.resource-sampler", qos: .utility)
    private let onSample: @Sendable (FireAPMResourceSample) -> Void
    private var timer: DispatchSourceTimer?
    private var isSceneActive = true
    private var boostedUntil = Date().addingTimeInterval(Constants.bootstrapBoostWindow)

    init(onSample: @escaping @Sendable (FireAPMResourceSample) -> Void) {
        self.onSample = onSample
    }

    func start() {
        guard timer == nil else { return }
        UIDevice.current.isBatteryMonitoringEnabled = true
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func setSceneActive(_ active: Bool) {
        queue.async {
            self.isSceneActive = active
        }
    }

    func boostSamplingWindow(duration: TimeInterval = Constants.bootstrapBoostWindow) {
        queue.async {
            self.boostedUntil = max(self.boostedUntil, Date().addingTimeInterval(duration))
        }
    }

    private func tick() {
        guard isSceneActive else { return }

        let now = Date()
        let interval = now < boostedUntil ? Constants.boostedInterval : Constants.defaultInterval
        timer?.schedule(deadline: .now() + interval, repeating: interval)

        let sample = FireAPMResourceSample(
            timestampUnixMs: FireAPMClock.nowUnixMs(date: now),
            cpuPercent: Self.currentCPUPercent(),
            residentSizeBytes: Self.currentResidentSize(),
            physicalFootprintBytes: Self.currentPhysicalFootprint(),
            thermalState: Self.thermalStateDescription(ProcessInfo.processInfo.thermalState),
            batteryState: Self.batteryStateDescription(UIDevice.current.batteryState),
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        onSample(sample)
    }

    private static func currentResidentSize() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return nil
        }
        return UInt64(info.resident_size)
    }

    private static func currentPhysicalFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return nil
        }
        return UInt64(info.phys_footprint)
    }

    private static func currentCPUPercent() -> Double? {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        guard result == KERN_SUCCESS, let threadList else {
            return nil
        }

        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: threadList),
                vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_t>.stride)
            )
        }

        var totalCPU: Double = 0
        for index in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var infoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
            let thread = threadList[index]
            let infoResult = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                    thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                }
            }
            guard infoResult == KERN_SUCCESS else {
                continue
            }
            if (info.flags & TH_FLAGS_IDLE) == 0 {
                totalCPU += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
            }
        }
        return totalCPU
    }

    private static func thermalStateDescription(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:
            return "nominal"
        case .fair:
            return "fair"
        case .serious:
            return "serious"
        case .critical:
            return "critical"
        @unknown default:
            return "unknown"
        }
    }

    private static func batteryStateDescription(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .unknown:
            return "unknown"
        case .unplugged:
            return "unplugged"
        case .charging:
            return "charging"
        case .full:
            return "full"
        @unknown default:
            return "unknown"
        }
    }
}
