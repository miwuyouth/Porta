import Foundation
import Network
import Security

private final class ConnectContext: @unchecked Sendable {
    private let lock = SafeLock()
    private var continuation: CheckedContinuation<NWAsyncConnection, Error>?
    private var timeoutItem: DispatchWorkItem?

    init(continuation: CheckedContinuation<NWAsyncConnection, Error>) {
        self.continuation = continuation
    }

    func setTimeoutItem(_ item: DispatchWorkItem) {
        lock.withLock {
            self.timeoutItem = item
        }
    }

    func resume(with result: Result<NWAsyncConnection, Error>) {
        let (cont, item) = lock.withLock { () -> (CheckedContinuation<NWAsyncConnection, Error>?, DispatchWorkItem?) in
            let c = continuation
            let t = timeoutItem
            continuation = nil
            timeoutItem = nil
            return (c, t)
        }
        item?.cancel()
        cont?.resume(with: result)
    }
}

public final class NWAsyncConnection: AsyncConnection, @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let lock = SafeLock()
    private var _isClosed: Bool = false
    private var readBuffer: Data = Data()

    public var isClosed: Bool {
        lock.withLock { _isClosed }
    }

    private init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    /// Factory method to establish a connection to host:port.
    public static func connect(
        host: String,
        port: Int,
        tlsEnable: Bool = false,
        tlsServerName: String? = nil,
        timeout: TimeInterval = 10
    ) async throws -> NWAsyncConnection {
        let endpointHost = NWEndpoint.Host(host)
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw AsyncConnectionError.connectionFailed("Invalid port: \(port)")
        }

        let parameters: NWParameters
        if tlsEnable {
            let tlsOptions = NWProtocolTLS.Options()
            if let serverName = tlsServerName ?? (host.isEmpty ? nil : host) {
                sec_protocol_options_set_tls_server_name(tlsOptions.securityProtocolOptions, serverName)
            }
            sec_protocol_options_set_verify_block(
                tlsOptions.securityProtocolOptions,
                { _, _, completion in
                    completion(true)
                },
                .global()
            )
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.enableKeepalive = true
            parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        } else {
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.enableKeepalive = true
            parameters = NWParameters(tls: nil, tcp: tcpOptions)
        }

        let nwConn = NWConnection(host: endpointHost, port: endpointPort, using: parameters)
        let queue = DispatchQueue(label: "swift.frp.nwconn.\(UUID().uuidString)")
        let asyncConn = NWAsyncConnection(connection: nwConn, queue: queue)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let context = ConnectContext(continuation: continuation)

                // Timeout timer for connection phase only
                let timeoutItem = DispatchWorkItem {
                    nwConn.cancel()
                    context.resume(with: .failure(AsyncConnectionError.timeout))
                }
                context.setTimeoutItem(timeoutItem)
                queue.asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

                nwConn.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        context.resume(with: .success(asyncConn))
                    case .failed(let error):
                        context.resume(with: .failure(AsyncConnectionError.connectionFailed(error.localizedDescription)))
                    case .cancelled:
                        context.resume(with: .failure(AsyncConnectionError.closed))
                    default:
                        break
                    }
                }

                nwConn.start(queue: queue)
            }
        } onCancel: {
            nwConn.cancel()
        }
    }

    public func read(upToCount maxCount: Int) async throws -> Data {
        guard !isClosed else {
            throw AsyncConnectionError.closed
        }

        let cachedChunk: Data? = lock.withLock {
            if !readBuffer.isEmpty {
                let countToTake = min(maxCount, readBuffer.count)
                let chunk = readBuffer.prefix(countToTake)
                readBuffer.removeFirst(countToTake)
                return Data(chunk)
            }
            return nil
        }

        if let chunk = cachedChunk {
            return chunk
        }

        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: maxCount) { [weak self] content, _, isComplete, error in
                guard let self = self else {
                    continuation.resume(throwing: AsyncConnectionError.closed)
                    return
                }

                if let error = error {
                    continuation.resume(throwing: AsyncConnectionError.readFailed(error.localizedDescription))
                    return
                }

                if let data = content, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    self.close()
                    continuation.resume(returning: Data())
                } else {
                    continuation.resume(returning: Data())
                }
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
                throw AsyncConnectionError.readFailed("Unexpected EOF: needed \(count) bytes, got \(accumulated.count)")
            }
            accumulated.append(chunk)
        }

        return accumulated
    }

    public func write(_ data: Data) async throws {
        guard !isClosed else {
            throw AsyncConnectionError.closed
        }
        guard !data.isEmpty else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: AsyncConnectionError.writeFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    public func close() {
        let shouldCancel = lock.withLock { () -> Bool in
            guard !_isClosed else { return false }
            _isClosed = true
            return true
        }

        if shouldCancel {
            connection.cancel()
        }
    }
}
