import Foundation

public protocol Connector: Sendable {
    func open() async throws
    func connect() async throws -> any AsyncConnection
    func close()
}

public final class DefaultConnector: Connector, @unchecked Sendable {
    private let config: FRPClientConfig
    private let lock = SafeLock()
    private var yamuxSession: YamuxSession?
    private var isClosed = false

    public init(config: FRPClientConfig) {
        self.config = config
    }

    public func open() async throws {
        guard config.transport.tcpMux else {
            return
        }

        let underlying = try await NWAsyncConnection.connect(
            host: config.serverAddr,
            port: config.serverPort,
            tlsEnable: config.transport.tlsEnable,
            tlsServerName: config.transport.tlsServerName,
            timeout: config.transport.dialServerTimeout
        )

        lock.withLock {
            self.yamuxSession = YamuxSession(underlying: underlying)
        }
    }

    public func connect() async throws -> any AsyncConnection {
        let (session, closed) = lock.withLock {
            (self.yamuxSession, self.isClosed)
        }

        guard !closed else {
            throw AsyncConnectionError.closed
        }

        if let session = session {
            return try await session.openStream()
        }

        // Direct connection without mux
        return try await NWAsyncConnection.connect(
            host: config.serverAddr,
            port: config.serverPort,
            tlsEnable: config.transport.tlsEnable,
            tlsServerName: config.transport.tlsServerName,
            timeout: config.transport.dialServerTimeout
        )
    }

    public func close() {
        let session = lock.withLock { () -> YamuxSession? in
            isClosed = true
            let s = yamuxSession
            yamuxSession = nil
            return s
        }

        session?.close()
    }
}
