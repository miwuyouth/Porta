import XCTest
import Foundation
@testable import FRPClient

/// End-to-end conformance tests benchmarking against official Go FRP test suites (`test/e2e`).
/// Specifically verifies wire protocol encryption and fault isolation:
/// An offline or failing local service must NEVER break the control connection or other proxies.
final class OfficialConformanceTests: XCTestCase {

    // MARK: - 1. Local Service Offline During Registration
    // In official FRP, local service availability is not probed at proxy registration time.
    // Proxies pointing to closed ports (e.g. Port 22 or 8080 when stopped) register cleanly
    // and the control connection stays alive with full heartbeat support.
    func testProxyRegistrationSucceedsWhenLocalServiceOffline() async throws {
        let (clientPipe, serverPipe) = MockPipeConnection.createPair()
        let connector = MockConnector(controlPair: (clientPipe, serverPipe))

        // Multiple proxies configured for offline local ports
        let sshProxy = FRPProxyConfig(name: "ssh", type: .tcp, localIP: "127.0.0.1", localPort: 22, remotePort: 60022)
        let webProxy = FRPProxyConfig(name: "web", type: .tcp, localIP: "127.0.0.1", localPort: 8080, remotePort: 60080)

        let clientConfig = FRPClientConfig(
            serverAddr: "127.0.0.1",
            serverPort: 7000,
            user: "user_test",
            auth: FRPAuthConfig(token: "test_secret_token"),
            transport: FRPTransportConfig(heartbeatInterval: 1),
            loginFailExit: true,
            proxies: [sshProxy, webProxy]
        )

        let serverTask = Task {
            // 1. Handshake in plaintext
            let loginMsg = try await serverPipe.readMessage() as! FRPLoginMessage
            XCTAssertEqual(loginMsg.user, "user_test")
            try await serverPipe.writeMessage(FRPLoginRespMessage(version: "0.61.0", runID: "run-e2e-offline", error: nil))

            // 2. Control connection encrypted with AES-128-CFB
            let encServer = CryptoConnection(wrapping: serverPipe, token: "test_secret_token")

            var registeredProxies = Set<String>()
            for _ in 0..<2 {
                let proxyMsg = try await encServer.readMessage() as! FRPNewProxyMessage
                registeredProxies.insert(proxyMsg.proxyName)
                try await encServer.writeMessage(FRPNewProxyRespMessage(
                    proxyName: proxyMsg.proxyName,
                    remoteAddr: "127.0.0.1:\(proxyMsg.remotePort ?? 0)",
                    error: nil
                ))
            }
            XCTAssertEqual(registeredProxies, ["ssh", "web"])

            // 3. Verify heartbeats flow continuously over the encrypted control connection
            let ping = try await encServer.readMessage()
            XCTAssertEqual(type(of: ping).messageType, .ping)
            try await encServer.writeMessage(FRPPongMessage())
        }

        let client = FRPClientService(config: clientConfig, connector: connector)
        try await client.start()

        let isRunning = await client.isRunningStatus
        XCTAssertTrue(isRunning, "Client must be running even if local ports 22 and 8080 are not listening")

        try await serverTask.value
        await client.stop()
    }

    // MARK: - 2. Inbound Work Connection Handling When Local Service is Offline
    // Tests official FRP fault isolation: when a user attempts to connect to a proxy whose
    // local backend is down (connection refused), FRP dials local, fails gracefully,
    // closes ONLY that work connection, and the main control connection MUST stay healthy.
    func testInboundWorkConnectionToOfflineLocalServiceDoesNotAffectControlConnection() async throws {
        let (controlClient, controlServer) = MockPipeConnection.createPair()
        let (workClient, workServer) = MockPipeConnection.createPair()

        let connector = MockConnector(
            controlPair: (controlClient, controlServer),
            workProvider: { (workClient, workServer) }
        )

        let sshProxy = FRPProxyConfig(name: "ssh", type: .tcp, localIP: "127.0.0.1", localPort: 22, remotePort: 60022)
        let clientConfig = FRPClientConfig(
            serverAddr: "127.0.0.1",
            serverPort: 7000,
            auth: FRPAuthConfig(token: "test_token"),
            transport: FRPTransportConfig(heartbeatInterval: 0),
            proxies: [sshProxy]
        )

        // Proxy handler with a dialer that simulates local connection refused
        let dialFailureExpected = expectation(description: "Local dial failure logged")
        let handler = DefaultProxyHandler(
            config: sshProxy,
            localDialer: { _, _ in
                throw AsyncConnectionError.connectionFailed("ECONNREFUSED: Connection refused to 127.0.0.1:22")
            },
            onLog: { _, msg in
                if msg.contains("连接本地服务 127.0.0.1:22 失败") {
                    dialFailureExpected.fulfill()
                }
            }
        )

        let client = FRPClientService(
            config: clientConfig,
            connector: connector,
            proxyHandlers: ["ssh": handler]
        )

        let serverTask = Task {
            // 1. Login
            _ = try await controlServer.readMessage() as! FRPLoginMessage
            try await controlServer.writeMessage(FRPLoginRespMessage(version: "0.61.0", runID: "run-offline-test", error: nil))

            let encControl = CryptoConnection(wrapping: controlServer, token: "test_token")

            // 2. NewProxy
            let pMsg = try await encControl.readMessage() as! FRPNewProxyMessage
            XCTAssertEqual(pMsg.proxyName, "ssh")
            try await encControl.writeMessage(FRPNewProxyRespMessage(proxyName: "ssh", remoteAddr: "127.0.0.1:60022", error: nil))

            // 3. Inbound request arrives from outside world -> Server asks client for work connection
            try await encControl.writeMessage(FRPReqWorkConnMessage())

            // 4. Server receives NewWorkConn on the work channel
            let workMsg = try await workServer.readMessage() as! FRPNewWorkConnMessage
            XCTAssertEqual(workMsg.runID, "run-offline-test")

            // 5. Server responds with StartWorkConn
            try await workServer.writeMessage(FRPStartWorkConnMessage(proxyName: "ssh"))

            // 6. Since local dial failed on the client side, the client must close the work connection!
            let eofCheck = try await workServer.read(upToCount: 1024)
            XCTAssertTrue(eofCheck.isEmpty, "Work connection should be closed by client when local service fails")

            // 7. CRITICAL VERIFICATION: Control connection MUST remain alive and responsive!
            try await encControl.writeMessage(FRPPingMessage())
            let pong = try await encControl.readMessage()
            XCTAssertEqual(type(of: pong).messageType, .pong, "Control connection must remain fully operational")
        }

        try await client.start()
        try await serverTask.value
        await fulfillment(of: [dialFailureExpected], timeout: 3.0)

        let isRunning = await client.isRunningStatus
        XCTAssertTrue(isRunning, "Client service must remain running after local dial failure")

        await client.stop()
    }

private final class AtomicBox<T>: @unchecked Sendable {
    private let lock = SafeLock()
    private var value: T

    init(_ value: T) {
        self.value = value
    }

    func get() -> T {
        lock.withLock { value }
    }

    func set(_ newValue: T) {
        lock.withLock { value = newValue }
    }

    func modify<R>(_ block: (inout T) -> R) -> R {
        lock.withLock { block(&value) }
    }
}

    // MARK: - 3. Local Service Dynamic Recovery
    // Verifies that if a local service is initially offline and then starts up later,
    // subsequent inbound connections succeed without needing to restart the FRP client.
    func testLocalServiceDynamicRecovery() async throws {
        let (controlClient, controlServer) = MockPipeConnection.createPair()
        let (workClient1, workServer1) = MockPipeConnection.createPair()
        let (workClient2, workServer2) = MockPipeConnection.createPair()
        let (localClient2, localServer2) = MockPipeConnection.createPair()

        let workCallCount = AtomicBox<Int>(0)

        let connector = MockConnector(
            controlPair: (controlClient, controlServer),
            workProvider: {
                let count = workCallCount.modify { $0 += 1; return $0 }
                return count == 1 ? (workClient1, workServer1) : (workClient2, workServer2)
            }
        )

        let webProxy = FRPProxyConfig(name: "web", type: .tcp, localIP: "127.0.0.1", localPort: 8080, remotePort: 60080)
        let clientConfig = FRPClientConfig(
            serverAddr: "127.0.0.1",
            serverPort: 7000,
            auth: FRPAuthConfig(token: "test_token"),
            transport: FRPTransportConfig(heartbeatInterval: 0),
            proxies: [webProxy]
        )

        let localServiceIsRunning = AtomicBox<Bool>(false)

        let handler = DefaultProxyHandler(
            config: webProxy,
            localDialer: { _, _ in
                if !localServiceIsRunning.get() {
                    throw AsyncConnectionError.connectionFailed("Local web service not running")
                }
                return localClient2
            }
        )

        let client = FRPClientService(
            config: clientConfig,
            connector: connector,
            proxyHandlers: ["web": handler]
        )

        let serverTask = Task {
            // Login & NewProxy
            _ = try await controlServer.readMessage() as! FRPLoginMessage
            try await controlServer.writeMessage(FRPLoginRespMessage(version: "0.61.0", runID: "run-dyn-test", error: nil))
            let encControl = CryptoConnection(wrapping: controlServer, token: "test_token")
            _ = try await encControl.readMessage() as! FRPNewProxyMessage
            try await encControl.writeMessage(FRPNewProxyRespMessage(proxyName: "web", remoteAddr: "127.0.0.1:60080", error: nil))

            // 1st request arrives: local service offline
            try await encControl.writeMessage(FRPReqWorkConnMessage())
            _ = try await workServer1.readMessage() as! FRPNewWorkConnMessage
            try await workServer1.writeMessage(FRPStartWorkConnMessage(proxyName: "web"))
            let eofCheck = try await workServer1.read(upToCount: 1024)
            XCTAssertTrue(eofCheck.isEmpty, "First work connection closes due to offline local service")

            // Simulate local service starting up now!
            localServiceIsRunning.set(true)

            // 2nd request arrives: local service is now ONLINE
            try await encControl.writeMessage(FRPReqWorkConnMessage())
            _ = try await workServer2.readMessage() as! FRPNewWorkConnMessage
            try await workServer2.writeMessage(FRPStartWorkConnMessage(proxyName: "web"))

            // Send HTTP request through work connection
            try await workServer2.write(Data("GET / HTTP/1.1\r\n\r\n".utf8))

            // Verify local server received it
            let localReq = try await localServer2.read(exactCount: 18)
            XCTAssertEqual(String(data: localReq, encoding: .utf8), "GET / HTTP/1.1\r\n\r\n")

            // Local server replies
            try await localServer2.write(Data("HTTP/1.1 200 OK\r\n".utf8))

            // Work connection receives the reply
            let workResp = try await workServer2.read(exactCount: 17)
            XCTAssertEqual(String(data: workResp, encoding: .utf8), "HTTP/1.1 200 OK\r\n")
        }

        try await client.start()
        try await serverTask.value
        await client.stop()
    }
}
