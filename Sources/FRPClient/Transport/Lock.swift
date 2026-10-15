import Foundation

public final class SafeLock: @unchecked Sendable {
    private let nsLock = NSLock()

    public init() {}

    @discardableResult
    public func withLock<T>(_ body: () throws -> T) rethrows -> T {
        nsLock.lock()
        defer { nsLock.unlock() }
        return try body()
    }
}
