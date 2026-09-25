import Foundation

public struct FireHostLogger: Sendable {
    private let target: String
    private let writeEntry: @Sendable (HostLogLevelState, String, String) -> Void

    init(
        target: String,
        writeEntry: @escaping @Sendable (HostLogLevelState, String, String) -> Void
    ) {
        self.target = target
        self.writeEntry = writeEntry
    }

    public func debug(_ message: @autoclosure () -> String) {
        writeEntry(.debug, target, message())
    }

    public func info(_ message: @autoclosure () -> String) {
        writeEntry(.info, target, message())
    }

    public func notice(_ message: @autoclosure () -> String) {
        writeEntry(.info, target, message())
    }

    public func warning(_ message: @autoclosure () -> String) {
        writeEntry(.warn, target, message())
    }

    public func error(_ message: @autoclosure () -> String) {
        writeEntry(.error, target, message())
    }
}
