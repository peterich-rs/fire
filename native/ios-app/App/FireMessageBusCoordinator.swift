import Foundation

struct FireMessageBusBufferedEventQueue {
    private static let maxBufferedEventCount = 64

    private var orderedKeys: [String] = []
    private var eventsByKey: [String: MessageBusEventState] = [:]

    var isEmpty: Bool {
        orderedKeys.isEmpty
    }

    mutating func enqueue(_ event: MessageBusEventState) {
        let key = Self.coalescingKey(for: event)
        if let existing = eventsByKey[key] {
            guard existing.messageId <= event.messageId else {
                return
            }
            eventsByKey[key] = event
            return
        }

        if orderedKeys.count >= Self.maxBufferedEventCount,
           let droppedKey = orderedKeys.first {
            orderedKeys.removeFirst()
            eventsByKey.removeValue(forKey: droppedKey)
        }

        orderedKeys.append(key)
        eventsByKey[key] = event
    }

    mutating func dequeueBatch(limit: Int) -> [MessageBusEventState] {
        guard limit > 0, !orderedKeys.isEmpty else {
            return []
        }

        let batchKeys = Array(orderedKeys.prefix(limit))
        orderedKeys.removeFirst(batchKeys.count)
        return batchKeys.compactMap { eventsByKey.removeValue(forKey: $0) }
    }

    private static func coalescingKey(for event: MessageBusEventState) -> String {
        let kind = String(describing: event.kind)
        switch event.kind {
        case .topicList, .topicDetail, .topicReaction, .presence, .notification:
            return "\(kind)|\(event.channel)"
        case .notificationAlert, .unknown:
            return "\(kind)|\(event.channel)|\(event.messageId)"
        }
    }
}

/// Bridges Rust-side MessageBus callbacks (called on arbitrary background threads)
/// to the Swift MainActor concurrency domain.
final class FireMessageBusCoordinator: MessageBusEventHandler, @unchecked Sendable {
    private static let deliveryBatchSize = 16

    private let lock = NSLock()
    private let onEvent: (MessageBusEventState) -> Void
    private var pendingEvents = FireMessageBusBufferedEventQueue()
    private var isDraining = false

    init(onEvent: @escaping (MessageBusEventState) -> Void) {
        self.onEvent = onEvent
    }

    func onMessageBusEvent(event: MessageBusEventState) {
        let shouldScheduleDrain = lock.withLock {
            pendingEvents.enqueue(event)
            guard !isDraining else {
                return false
            }
            isDraining = true
            return true
        }

        guard shouldScheduleDrain else {
            return
        }

        Task { [weak self] in
            await self?.drainPendingEvents()
        }
    }

    private func drainBatch() -> [MessageBusEventState] {
        lock.withLock {
            let batch = pendingEvents.dequeueBatch(limit: Self.deliveryBatchSize)
            if batch.isEmpty {
                isDraining = false
            }
            return batch
        }
    }

    private func drainPendingEvents() async {
        while true {
            let batch = drainBatch()
            guard !batch.isEmpty else {
                return
            }

            let handler = onEvent
            await MainActor.run {
                for event in batch {
                    handler(event)
                }
            }
        }
    }
}
