import Foundation

/// Bridges Rust-side MessageBus callbacks (called on arbitrary background threads)
/// to the Swift MainActor concurrency domain.
final class FireMessageBusCoordinator: MessageBusEventHandler, @unchecked Sendable {
    private let onEvent: (MessageBusEventState) -> Void

    init(onEvent: @escaping (MessageBusEventState) -> Void) {
        self.onEvent = onEvent
    }

    func onMessageBusEvent(event: MessageBusEventState) {
        let handler = onEvent
        let captured = event
        Task { @MainActor in
            handler(captured)
        }
    }
}
