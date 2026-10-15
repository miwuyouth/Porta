import Foundation

public final class YamuxStream: AsyncConnection, @unchecked Sendable {
    public let id: UInt32
    private weak var session: YamuxSession?

    private struct ReadWaiter {
        let maxCount: Int
        let continuation: CheckedContinuation<Data, Error>
    }

    private let lock = SafeLock()
    private var _isClosed: Bool = false
    private var readBuffer = Data()
    private var readWaiters: [ReadWaiter] = []

    // Flow control
    private var sendWindow: Int32 = 256 * 1024
    private var recvWindow: Int32 = 256 * 1024
    private let initialRecvWindow: Int32 = 256 * 1024

    public var isClosed: Bool {
        lock.withLock { _isClosed }
    }

    public init(id: UInt32, session: YamuxSession) {
        self.id = id
        self.session = session
    }

    // Called by YamuxSession when data arrives for this stream
    internal func pushData(_ data: Data) {
        var waitersToResume: [(CheckedContinuation<Data, Error>, Data)] = []
        var shouldUpdateWindow = false
        var delta: Int32 = 0

        lock.withLock {
            guard !_isClosed else { return }

            readBuffer.append(data)
            recvWindow -= Int32(data.count)

            if recvWindow < (initialRecvWindow / 2) {
                shouldUpdateWindow = true
                delta = initialRecvWindow - recvWindow
                recvWindow = initialRecvWindow
            }

            while let waiter = readWaiters.first, !readBuffer.isEmpty {
                readWaiters.removeFirst()
                let count = min(waiter.maxCount, readBuffer.count)
                let chunk = readBuffer.prefix(count)
                readBuffer.removeFirst(count)
                waitersToResume.append((waiter.continuation, Data(chunk)))
            }
        }

        for (waiter, chunk) in waitersToResume {
            waiter.resume(returning: chunk)
        }

        if shouldUpdateWindow, let session = session {
            Task {
                try? await session.sendWindowUpdate(streamID: self.id, delta: UInt32(delta))
            }
        }
    }

    internal func updateSendWindow(delta: UInt32) {
        lock.withLock {
            sendWindow += Int32(delta)
        }
    }

    internal func handleRemoteClose() {
        let waitersToResume = lock.withLock { () -> [(CheckedContinuation<Data, Error>, Data)] in
            _isClosed = true
            var list: [(CheckedContinuation<Data, Error>, Data)] = []
            while let waiter = readWaiters.first {
                readWaiters.removeFirst()
                if !readBuffer.isEmpty {
                    let count = min(waiter.maxCount, readBuffer.count)
                    let chunk = readBuffer.prefix(count)
                    readBuffer.removeFirst(count)
                    list.append((waiter.continuation, Data(chunk)))
                } else {
                    list.append((waiter.continuation, Data()))
                }
            }
            return list
        }

        for (waiter, chunk) in waitersToResume {
            waiter.resume(returning: chunk)
        }
    }

    public func read(upToCount maxCount: Int) async throws -> Data {
        let immediateData: Data? = lock.withLock {
            if !readBuffer.isEmpty {
                let count = min(maxCount, readBuffer.count)
                let chunk = readBuffer.prefix(count)
                readBuffer.removeFirst(count)
                return Data(chunk)
            }
            if _isClosed {
                return Data()
            }
            return nil
        }

        if let data = immediateData {
            return data
        }

        return try await withCheckedThrowingContinuation { continuation in
            let added = lock.withLock { () -> Bool in
                if _isClosed {
                    return false
                }
                readWaiters.append(ReadWaiter(maxCount: maxCount, continuation: continuation))
                return true
            }

            if !added {
                continuation.resume(returning: Data())
            }
        }
    }

    public func read(exactCount count: Int) async throws -> Data {
        guard count > 0 else { return Data() }

        var accumulated = Data()
        accumulated.reserveCapacity(count)

        while accumulated.count < count {
            let needed = count - accumulated.count
            let chunk = try await read(upToCount: needed)
            if chunk.isEmpty {
                throw AsyncConnectionError.readFailed("YamuxStream unexpected EOF (expected \(count), got \(accumulated.count))")
            }
            if chunk.count > needed {
                accumulated.append(chunk.prefix(needed))
                let extra = chunk.dropFirst(needed)
                lock.withLock {
                    readBuffer.insert(contentsOf: extra, at: 0)
                }
            } else {
                accumulated.append(chunk)
            }
        }

        return accumulated
    }

    public func write(_ data: Data) async throws {
        guard let session = session, !isClosed else {
            throw AsyncConnectionError.closed
        }
        guard !data.isEmpty else { return }

        // Send data in chunks of max 64KB
        let chunkSize = 64 * 1024
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            let chunk = data.subdata(in: offset..<end)
            try await session.sendDataFrame(streamID: id, data: chunk, flags: [])
            offset = end
        }
    }

    public func close() {
        let waiters = lock.withLock { () -> [ReadWaiter] in
            guard !_isClosed else { return [] }
            _isClosed = true
            let w = readWaiters
            readWaiters.removeAll()
            return w
        }

        for waiter in waiters {
            waiter.continuation.resume(returning: Data())
        }

        if let session = session {
            Task {
                try? await session.sendStreamClose(streamID: self.id)
            }
        }
    }
}
