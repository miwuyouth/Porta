import XCTest
import Network
@testable import FRPClient

final class IntegrationTests: XCTestCase {

    // MARK: - 1. Real Network Listener Test

    func testMockServerHandshakeAndPing() async throws {
        // Find an available port by binding NWListener
        let port: UInt16 = 18702
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            XCTFail("Invalid port")
            return
        }

        let parameters = NWParameters.tcp
        let listener = try NWListener(using: parameters, on: nwPort)
        let queue = DispatchQueue(label: "mock.frps.queue")

        let loginReceived = expectation(description: "Login message received")
        let proxyReceived = expectation(description: "NewProxy message received")

        listener.newConnectionHandler = { newConn in
            newConn.start(queue: queue)

            Task {
                let serverConn = MockNWAsyncConnection(nwConn: newConn, queue: queue)
                do {
                    // 1. Read Login
                    let msg1 = try await serverConn.readMessage()
                    if let login = msg1 as? FRPLoginMessage {
                        XCTAssertEqual(login.user, "test_user")
                        loginReceived.fulfill()

                        // Send LoginResp
                        let resp = FRPLoginRespMessage(version: "0.61.0", runID: "run-mock-123", error: nil)
                        try await serverConn.writeMessage(resp)
                    }

                    // Wrap server connection in CryptoConnection to match FRP wire protocol
                    let encryptedServerConn = CryptoConnection(wrapping: serverConn, token: "secret_123")

                    // 2. Read NewProxy
                    let msg2 = try await encryptedServerConn.readMessage()
                    if let proxy = msg2 as? FRPNewProxyMessage {
                        XCTAssertEqual(proxy.proxyName, "mock_tcp")
                        XCTAssertEqual(proxy.remotePort, 19000)
                        proxyReceived.fulfill()

                        // Send NewProxyResp
                        let resp = FRPNewProxyRespMessage(proxyName: "mock_tcp", remoteAddr: "127.0.0.1:19000", error: nil)
                        try await encryptedServerConn.writeMessage(resp)
                    }
                } catch {
                    // Connection closed or done
                }
            }
        }

        listener.start(queue: queue)
        defer { listener.cancel() }

        // Give listener a brief moment to open socket
        try await Task.sleep(nanoseconds: 100_000_000)

        // Setup Client
        let proxyConfig = FRPProxyConfig(
            name: "mock_tcp",
            type: .tcp,
            localIP: "127.0.0.1",
            localPort: 8080,
            remotePort: 19000
        )
        let clientConfig = FRPClientConfig(
            serverAddr: "127.0.0.1",
            serverPort: Int(port),
            user: "test_user",
            auth: FRPAuthConfig(token: "secret_123"),
            transport: FRPTransportConfig(
                tcpMux: false,
                heartbeatInterval: 2,
                dialServerTimeout: 5
            ),
            loginFailExit: true,
            proxies: [proxyConfig]
        )

        let client = FRPClientService(config: clientConfig)
        try await client.start()

        await fulfillment(of: [loginReceived, proxyReceived], timeout: 5.0)

        await client.stop()
    }

    // MARK: - 2. In-Memory Mock Server Handshake & Multi-Proxy Registration

    func testClientServiceLoginAndMultiProxyRegistrationInMemory() async throws {
        let (clientPipe, serverPipe) = MockPipeConnection.createPair()
        let connector = MockConnector(controlPair: (clientPipe, serverPipe))

        let p1 = FRPProxyConfig(name: "tcp_tunnel", type: .tcp, localIP: "127.0.0.1", localPort: 8080, remotePort: 18080)
        let p2 = FRPProxyConfig(name: "http_site", type: .http, localIP: "127.0.0.1", localPort: 3000, customDomains: ["test.local"])

        let clientConfig = FRPClientConfig(
            serverAddr: "127.0.0.1",
            serverPort: 7000,
            user: "alice",
            auth: FRPAuthConfig(token: "token123"),
            transport: FRPTransportConfig(heartbeatInterval: 0),
            loginFailExit: true,
            proxies: [p1, p2]
        )

        let serverTask = Task {
            // Read Login
            let loginMsg = try await serverPipe.readMessage() as! FRPLoginMessage
            XCTAssertEqual(loginMsg.user, "alice")
            try await serverPipe.writeMessage(FRPLoginRespMessage(version: "0.61.0", runID: "run-abc", error: nil))

            let encServer = CryptoConnection(wrapping: serverPipe, token: "token123")
            // Read Proxy registrations (order independent)
            for _ in 0..<2 {
                let proxyMsg = try await encServer.readMessage() as! FRPNewProxyMessage
                XCTAssertTrue(proxyMsg.proxyName == "tcp_tunnel" || proxyMsg.proxyName == "http_site")
                try await encServer.writeMessage(FRPNewProxyRespMessage(
                    proxyName: proxyMsg.proxyName,
                    remoteAddr: "127.0.0.1:18080",
                    error: nil
                ))
            }
        }

        let client = FRPClientService(config: clientConfig, connector: connector)
        try await client.start()

        try await serverTask.value
        await client.stop()
    }

    // MARK: - 3. Login Rejection Handling

    func testClientServiceLoginRejection() async throws {
        let (clientPipe, serverPipe) = MockPipeConnection.createPair()
        let connector = MockConnector(controlPair: (clientPipe, serverPipe))

        let clientConfig = FRPClientConfig(
            serverAddr: "127.0.0.1",
            serverPort: 7000,
            auth: FRPAuthConfig(token: "wrong_token"),
            transport: FRPTransportConfig(heartbeatInterval: 0),
            proxies: []
        )

        let serverTask = Task {
            _ = try await serverPipe.readMessage() as! FRPLoginMessage
            // Return authorization error
            try await serverPipe.writeMessage(FRPLoginRespMessage(version: "0.61.0", runID: nil, error: "token authorization failed"))
        }

        let client = FRPClientService(config: clientConfig, connector: connector)

        do {
            try await client.start()
            XCTFail("Should have failed login")
        } catch {
            guard case FRPClientError.loginFailed(let msg) = error else {
                XCTFail("Expected FRPClientError.loginFailed, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("token authorization failed"))
        }

        try await serverTask.value
    }

    // MARK: - 4. Proxy Registration Rejection Handling

    func testClientServiceProxyRegistrationRejection() async throws {
        let (clientPipe, serverPipe) = MockPipeConnection.createPair()
        let connector = MockConnector(controlPair: (clientPipe, serverPipe))

        let p1 = FRPProxyConfig(name: "conflict_proxy", type: .tcp, localIP: "127.0.0.1", localPort: 8080, remotePort: 18080)

        let clientConfig = FRPClientConfig(
            serverAddr: "127.0.0.1",
            serverPort: 7000,
            auth: FRPAuthConfig(token: "token123"),
            transport: FRPTransportConfig(heartbeatInterval: 0),
            loginFailExit: true,
            proxies: [p1]
        )

        let serverTask = Task {
            _ = try await serverPipe.readMessage() as! FRPLoginMessage
            try await serverPipe.writeMessage(FRPLoginRespMessage(version: "0.61.0", runID: "run-abc", error: nil))

            let encServer = CryptoConnection(wrapping: serverPipe, token: "token123")
            _ = try await encServer.readMessage() as! FRPNewProxyMessage
            // Return proxy registration error
            try await encServer.writeMessage(FRPNewProxyRespMessage(proxyName: "conflict_proxy", remoteAddr: nil, error: "port [18080] already bound"))
        }

        let client = FRPClientService(config: clientConfig, connector: connector)

        do {
            try await client.start()
            XCTFail("Should have failed proxy registration")
        } catch {
            guard case FRPClientError.proxyRegisterFailed(let name, let errorMsg) = error else {
                XCTFail("Expected FRPClientError.proxyRegisterFailed, got \(error)")
                return
            }
            XCTAssertEqual(name, "conflict_proxy")
            XCTAssertTrue(errorMsg.contains("already bound"))
        }

        try await serverTask.value
    }

    // MARK: - 5. Full End-to-End Work Connection Data Relay

    func testFullEndToEndWorkConnectionDataRelay() async throws {
        let (controlClient, controlServer) = MockPipeConnection.createPair()
        let (workClient, workServer) = MockPipeConnection.createPair()
        let (localClient, localServer) = MockPipeConnection.createPair()

        let connector = MockConnector(
            controlPair: (controlClient, controlServer),
            workProvider: { (workClient, workServer) }
        )

        let proxyConfig = FRPProxyConfig(
            name: "echo_service",
            type: .tcp,
            localIP: "127.0.0.1",
            localPort: 9000,
            remotePort: 19000
        )

        let clientConfig = FRPClientConfig(
            serverAddr: "127.0.0.1",
            serverPort: 7000,
            auth: FRPAuthConfig(token: "test_token"),
            transport: FRPTransportConfig(heartbeatInterval: 0),
            proxies: [proxyConfig]
        )

        // Local echo mock service
        let localEchoTask = Task {
            let requestData = try await localServer.read(exactCount: 4)
            XCTAssertEqual(requestData, Data("PING".utf8))
            try await localServer.write(Data("PONG".utf8))
        }

        // Custom proxy handler injecting the local service dialer
        let handler = DefaultProxyHandler(config: proxyConfig, localDialer: { _, _ in
            return localClient
        })

        let client = FRPClientService(
            config: clientConfig,
            connector: connector,
            proxyHandlers: ["echo_service": handler]
        )

        // Server control loop
        let serverTask = Task {
            // 1. Login
            _ = try await controlServer.readMessage() as! FRPLoginMessage
            try await controlServer.writeMessage(FRPLoginRespMessage(version: "0.61.0", runID: "run-relay-test", error: nil))

            let encControlServer = CryptoConnection(wrapping: controlServer, token: "test_token")

            // 2. NewProxy
            _ = try await encControlServer.readMessage() as! FRPNewProxyMessage
            try await encControlServer.writeMessage(FRPNewProxyRespMessage(proxyName: "echo_service", remoteAddr: "127.0.0.1:19000", error: nil))

            // 3. Server instructs client to open work connection
            try await encControlServer.writeMessage(FRPReqWorkConnMessage())

            // 4. Server accepts work connection from client
            let newWorkMsg = try await workServer.readMessage() as! FRPNewWorkConnMessage
            XCTAssertEqual(newWorkMsg.runID, "run-relay-test")

            // 5. Server responds with StartWorkConn
            try await workServer.writeMessage(FRPStartWorkConnMessage(proxyName: "echo_service"))

            // 6. Server sends PING to work connection
            try await workServer.write(Data("PING".utf8))

            // 7. Server reads PONG back from work connection (forwarded via local service!)
            let response = try await workServer.read(exactCount: 4)
            XCTAssertEqual(response, Data("PONG".utf8))
        }

        try await client.start()
        try await serverTask.value
        try await localEchoTask.value

        await client.stop()
    }
}

// MARK: - Private Helper for NWListener Test
private final class MockNWAsyncConnection: AsyncConnection, @unchecked Sendable {
    private let nwConn: NWConnection
    private let queue: DispatchQueue
    private let lock = SafeLock()
    private var _isClosed = false
    private var readBuffer = Data()

    var isClosed: Bool {
        lock.withLock { _isClosed }
    }

    init(nwConn: NWConnection, queue: DispatchQueue) {
        self.nwConn = nwConn
        self.queue = queue
    }

    func read(upToCount maxCount: Int) async throws -> Data {
        guard !isClosed else { throw AsyncConnectionError.closed }

        return try await withCheckedThrowingContinuation { continuation in
            nwConn.receive(minimumIncompleteLength: 1, maximumLength: maxCount) { content, _, isComplete, error in
                if let error = error {
                    continuation.resume(throwing: AsyncConnectionError.readFailed(error.localizedDescription))
                } else if let data = content, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(returning: Data())
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }

    func read(exactCount count: Int) async throws -> Data {
        var accumulated = Data()
        accumulated.reserveCapacity(count)

        while accumulated.count < count {
            let needed = count - accumulated.count
            let chunk = try await read(upToCount: needed)
            if chunk.isEmpty {
                throw AsyncConnectionError.readFailed("EOF")
            }
            accumulated.append(chunk)
        }
        return accumulated
    }

    func write(_ data: Data) async throws {
        guard !isClosed else { throw AsyncConnectionError.closed }

        return try await withCheckedThrowingContinuation { continuation in
            nwConn.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: AsyncConnectionError.writeFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }

    func close() {
        lock.withLock {
            _isClosed = true
        }
        nwConn.cancel()
    }
}
