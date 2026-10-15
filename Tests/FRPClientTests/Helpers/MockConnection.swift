import Foundation
@testable import FRPClient

/// An in-memory bidirectional asynchronous connection pair for unit and integration testing.
public final class MockPipeConnection: AsyncConnection, @unchecked Sendable {
    private struct Waiter {
        let maxCount: Int
        let continuation: CheckedContinuation<Data, Error>
    }

    private let lock = SafeLock()
    private var buffer = Data()
    private var waiters: [Waiter] = []
    private var _isClosed = false
    private var _isPeerClosed = false
    private let otherSide: MockPipeConnection?
    private var peerRef: MockPipeConnection?

    public var isClosed: Bool {
        lock.withLock { _isClosed }
    }

    private init(peer: MockPipeConnection? = nil) {
        self.otherSide = peer
    }

    private var targetPeer: MockPipeConnection? {
        otherSide ?? peerRef
    }

    /// Creates a connected pair of in-memory connections (A <-> B).
    public static func createPair() -> (MockPipeConnection, MockPipeConnection) {
        let connA = MockPipeConnection()
        let connB = MockPipeConnection(peer: connA)
        connA.peerRef = connB
        return (connA, connB)
    }

    public func read(upToCount maxCount: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                if !buffer.isEmpty {
                    let count = min(maxCount, buffer.count)
                    let chunk = buffer.prefix(count)
                    buffer.removeFirst(count)
                    continuation.resume(returning: Data(chunk))
                } else if _isClosed || _isPeerClosed {
                    continuation.resume(returning: Data()) // EOF
                } else {
                    waiters.append(Waiter(maxCount: maxCount, continuation: continuation))
                }
            }
        }
    }

    public func read(exactCount count: Int) async throws -> Data {
        guard count > 0 else { return Data() }
        var result = Data()
        result.reserveCapacity(count)

        while result.count < count {
            let needed = count - result.count
            let chunk = try await read(upToCount: needed)
            if chunk.isEmpty {
                throw AsyncConnectionError.readFailed("MockPipeConnection EOF reached while expecting \(count) bytes (got \(result.count))")
            }
            result.append(chunk)
        }
        return result
    }

    public func write(_ data: Data) async throws {
        let (closed, peer) = lock.withLock { (_isClosed, targetPeer) }
        guard !closed else { throw AsyncConnectionError.closed }
        guard let p = peer, !p.isClosed else { throw AsyncConnectionError.closed }

        p.receiveIncoming(data)
    }

    fileprivate func receiveIncoming(_ data: Data) {
        var actions: [(CheckedContinuation<Data, Error>, Data)] = []
        lock.withLock {
            buffer.append(data)
            while !waiters.isEmpty && !buffer.isEmpty {
                let waiter = waiters.removeFirst()
                let count = min(waiter.maxCount, buffer.count)
                let chunk = Data(buffer.prefix(count))
                buffer.removeFirst(count)
                actions.append((waiter.continuation, chunk))
            }
        }
        for (continuation, chunk) in actions {
            continuation.resume(returning: chunk)
        }
    }

    fileprivate func notifyPeerClosed() {
        var pendingWaiters: [Waiter] = []
        lock.withLock {
            _isPeerClosed = true
            pendingWaiters = waiters
            waiters.removeAll()
        }
        for w in pendingWaiters {
            w.continuation.resume(returning: Data()) // EOF
        }
    }

    public func close() {
        var pendingWaiters: [Waiter] = []
        let peer = targetPeer
        lock.withLock {
            guard !_isClosed else { return }
            _isClosed = true
            pendingWaiters = waiters
            waiters.removeAll()
        }
        for w in pendingWaiters {
            w.continuation.resume(returning: Data()) // EOF
        }
        peer?.notifyPeerClosed()
    }
}

/// A mock Connector for testing FRPClientService without touching real network sockets.
public final class MockConnector: Connector, @unchecked Sendable {
    private let controlConnectionPair: (client: MockPipeConnection, server: MockPipeConnection)
    private let workConnectionProvider: @Sendable () -> (client: MockPipeConnection, server: MockPipeConnection)
    private let lock = SafeLock()
    private var isFirstConnect = true
    private var _isClosed = false

    public init(
        controlPair: (client: MockPipeConnection, server: MockPipeConnection)? = nil,
        workProvider: (@Sendable () -> (client: MockPipeConnection, server: MockPipeConnection))? = nil
    ) {
        self.controlConnectionPair = controlPair ?? MockPipeConnection.createPair()
        self.workConnectionProvider = workProvider ?? { MockPipeConnection.createPair() }
    }

    public var serverControlConnection: MockPipeConnection {
        controlConnectionPair.server
    }

    public func open() async throws {
        // Mock open
    }

    public func connect() async throws -> any AsyncConnection {
        lock.withLock {
            if isFirstConnect {
                isFirstConnect = false
                return controlConnectionPair.client
            } else {
                let pair = workConnectionProvider()
                return pair.client
            }
        }
    }

    public func close() {
        lock.withLock {
            _isClosed = true
        }
        controlConnectionPair.client.close()
        controlConnectionPair.server.close()
    }
}
