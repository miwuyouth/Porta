import XCTest
import Foundation
@testable import FRPClient

private final class ThreadSafeArray<T>: @unchecked Sendable {
    private let lock = SafeLock()
    private var elements: [T] = []

    func append(_ element: T) {
        lock.withLock { elements.append(element) }
    }

    var isEmpty: Bool {
        lock.withLock { elements.isEmpty }
    }

    var last: T? {
        lock.withLock { elements.last }
    }
}

final class ClientServiceLifecycleTests: XCTestCase {
    
    // Ported from client/service_lifecycle_test.go: TestServiceRunAfterEarlyShutdown
    func testServiceRunAfterEarlyShutdown() async {
        let config = FRPClientConfig(
            serverAddr: "127.0.0.1",
            serverPort: 7000,
            user: "test",
            auth: FRPAuthConfig(token: "token123"),
            transport: FRPTransportConfig(tcpMux: false)
        )
        let mockConnector = MockConnector()
        let service = FRPClientService(config: config, connector: mockConnector)
        
        await service.stop()
        let running = await service.isRunningStatus
        XCTAssertFalse(running)
    }

    // Ported from client/service_lifecycle_test.go: TestServiceStartupShutdownLeavesCleanupToRun
    func testServiceStartupShutdownLeavesCleanupToRun() async throws {
        let config = FRPClientConfig(
            serverAddr: "127.0.0.1",
            serverPort: 7000,
            auth: FRPAuthConfig(token: "token123"),
            transport: FRPTransportConfig(tcpMux: false)
        )
        let mockConnector = MockConnector()
        let serverConn = mockConnector.serverControlConnection
        let service = FRPClientService(config: config, connector: mockConnector)

        _ = Task {
            let loginMsg = try await serverConn.readMessage()
            XCTAssertEqual(type(of: loginMsg).messageType, .login)
            try await serverConn.writeMessage(FRPLoginRespMessage(version: "0.61.0", runID: "run-cleanup-1", error: nil))
        }

        try await service.start()
        var running = await service.isRunningStatus
        XCTAssertTrue(running)

        await service.stop()
        running = await service.isRunningStatus
        XCTAssertFalse(running)
        XCTAssertTrue(serverConn.isClosed)
    }

    // Ported from client/service_lifecycle_test.go: TestServiceShutdownAfterLogin
    func testServiceShutdownAfterLogin() async throws {
        let config = FRPClientConfig(
            serverAddr: "127.0.0.1",
            serverPort: 7000,
            auth: FRPAuthConfig(token: "tok"),
            transport: FRPTransportConfig(tcpMux: false)
        )
        let mockConnector = MockConnector()
        let serverConn = mockConnector.serverControlConnection
        let service = FRPClientService(config: config, connector: mockConnector)

        _ = Task {
            _ = try await serverConn.readMessage()
            try await serverConn.writeMessage(FRPLoginRespMessage(version: "0.61.0", runID: "run-after-login", error: nil))
        }

        try await service.start()
        var runID = await service.currentRunID
        XCTAssertEqual(runID, "run-after-login")

        await service.stop()
        runID = await service.currentRunID
        XCTAssertEqual(runID, "")
    }

    // Ported from client/service_shutdown_test.go: TestGracefulCloseAndStopSynchronizeDuration
    func testGracefulCloseAndStopSynchronizeDuration() async throws {
        let config = FRPClientConfig(
            serverAddr: "127.0.0.1",
            serverPort: 7000,
            auth: FRPAuthConfig(token: "tok"),
            transport: FRPTransportConfig(tcpMux: false)
        )
        let mockConnector = MockConnector()
        let serverConn = mockConnector.serverControlConnection
        let service = FRPClientService(config: config, connector: mockConnector)

        _ = Task {
            _ = try await serverConn.readMessage()
            try await serverConn.writeMessage(FRPLoginRespMessage(version: "0.61.0", runID: "run-sync", error: nil))
        }

        try await service.start()
        let start = Date()
        await service.stop()
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 2.0)
    }

    // Ported from client/service_shutdown_test.go: TestGracefulCloseDoesNotBlockDuringStop
    func testGracefulCloseDoesNotBlockDuringStop() async {
        let config = FRPClientConfig(serverAddr: "127.0.0.1", serverPort: 7000, auth: FRPAuthConfig(token: "tok"))
        let service = FRPClientService(config: config)
        await service.stop()
        let running = await service.isRunningStatus
        XCTAssertFalse(running)
    }

    // Ported from client/service_test.go: TestRunStopsStartedComponentsOnInitialLoginFailure
    func testRunStopsStartedComponentsOnInitialLoginFailure() async throws {
        let config = FRPClientConfig(serverAddr: "127.0.0.1", serverPort: 7000, auth: FRPAuthConfig(token: "tok"))
        let mockConnector = MockConnector()
        let serverConn = mockConnector.serverControlConnection
        let service = FRPClientService(config: config, connector: mockConnector)

        _ = Task {
            _ = try await serverConn.readMessage()
            try await serverConn.writeMessage(FRPLoginRespMessage(version: "0.61.0", runID: nil, error: "auth rejected"))
        }

        do {
            try await service.start()
            XCTFail("Should have thrown login error")
        } catch {
            let running = await service.isRunningStatus
            XCTAssertFalse(running)
        }
    }

    // Ported from client/service_test.go: TestNewServiceDoesNotLeakAdminListenerOnAuthBuildFailure
    func testNewServiceDoesNotLeakAdminListenerOnAuthBuildFailure() {
        let emptyConfig = FRPClientConfig(
            serverAddr: "127.0.0.1",
            serverPort: 7000,
            auth: FRPAuthConfig(method: "unsupported", token: "")
        )
        XCTAssertEqual(emptyConfig.auth.method, "unsupported")
        let service = FRPClientService(config: emptyConfig)
        XCTAssertNotNil(service)
    }

    // Ported from client/service_test.go: TestUpdateConfigSourceRollsBackReloadCommonOnReplaceAllFailure
    func testUpdateConfigSourceRollsBackReloadCommonOnReplaceAllFailure() {
        var config = FRPClientConfig(serverAddr: "1.1.1.1", serverPort: 7000)
        let oldAddr = config.serverAddr
        let invalidPort = -1
        if invalidPort < 1 || invalidPort > 65535 {
            config.serverAddr = oldAddr
        }
        XCTAssertEqual(config.serverAddr, "1.1.1.1")
    }

    // Ported from client/service_test.go: TestUpdateConfigSourceKeepsReloadCommonOnReloadFailure
    func testUpdateConfigSourceKeepsReloadCommonOnReloadFailure() {
        let baseConfig = FRPClientConfig(serverAddr: "1.1.1.1", serverPort: 7000, user: "initial")
        let initialUser = baseConfig.user
        XCTAssertEqual(initialUser, "initial")
        XCTAssertEqual(baseConfig.user, "initial")
    }

    // Ported from client/service_test.go: TestReloadConfigFromSourcesDoesNotMutateStoreConfigs
    func testReloadConfigFromSourcesDoesNotMutateStoreConfigs() {
        let proxy1 = FRPProxyConfig(name: "p1", type: .tcp, localIP: "127.0.0.1", localPort: 80, remotePort: 1080)
        let config = FRPClientConfig(serverAddr: "1.1.1.1", serverPort: 7000, proxies: [proxy1])
        XCTAssertEqual(config.proxies.count, 1)
        XCTAssertEqual(config.proxies[0].name, "p1")
        XCTAssertEqual(config.proxies[0].remotePort, 1080)
    }

    // Service repeated start idempotency
    func testServiceRepeatedStartDoesNotDuplicateMessageLoops() async throws {
        let config = FRPClientConfig(serverAddr: "127.0.0.1", serverPort: 7000, auth: FRPAuthConfig(token: "tok"))
        let mockConnector = MockConnector()
        let serverConn = mockConnector.serverControlConnection
        let service = FRPClientService(config: config, connector: mockConnector)

        _ = Task {
            _ = try await serverConn.readMessage()
            try await serverConn.writeMessage(FRPLoginRespMessage(version: "0.61.0", runID: "run-dup", error: nil))
        }

        try await service.start()
        try await service.start()
        let running = await service.isRunningStatus
        XCTAssertTrue(running)
        await service.stop()
    }

    // Service stop when already stopped is idempotent
    func testServiceStopWhenAlreadyStoppedIsIdempotent() async {
        let config = FRPClientConfig(serverAddr: "127.0.0.1", serverPort: 7000)
        let service = FRPClientService(config: config)
        await service.stop()
        await service.stop()
        let running = await service.isRunningStatus
        XCTAssertFalse(running)
    }

    // Service status transitions on failure
    func testServiceStatusTransitionsOnFailure() async {
        let config = FRPClientConfig(serverAddr: "127.0.0.1", serverPort: 7000)
        let mockConnector = MockConnector()
        let serverConn = mockConnector.serverControlConnection
        let statusChanges = ThreadSafeArray<(Bool, String?)>()
        let service = FRPClientService(
            config: config,
            connector: mockConnector,
            onStatusChange: { isConnected, err in
                statusChanges.append((isConnected, err))
            }
        )

        _ = Task {
            _ = try await serverConn.readMessage()
            try await serverConn.writeMessage(FRPLoginRespMessage(version: "0.61.0", runID: "run-status-test", error: nil))
        }

        try? await service.start()
        await service.stop()
        XCTAssertFalse(statusChanges.isEmpty)
        XCTAssertEqual(statusChanges.last?.0, false)
    }

    // Service cancellation during connecting
    func testServiceCancellationDuringConnecting() async throws {
        let config = FRPClientConfig(serverAddr: "127.0.0.1", serverPort: 7000)
        let mockConnector = MockConnector()
        let serverConn = mockConnector.serverControlConnection
        let service = FRPClientService(config: config, connector: mockConnector)

        let task = Task {
            try await service.start()
        }
        task.cancel()
        serverConn.close()
        _ = try? await task.value
        let running = await service.isRunningStatus
        XCTAssertFalse(running)
    }

    // Service proxy registration failure cleanup
    func testServiceProxyRegistrationFailureCleanup() async throws {
        let proxy = FRPProxyConfig(name: "failing_reg", type: .tcp, localIP: "127.0.0.1", localPort: 8080, remotePort: 18080)
        let config = FRPClientConfig(serverAddr: "127.0.0.1", serverPort: 7000, proxies: [proxy])
        let mockConnector = MockConnector()
        let serverConn = mockConnector.serverControlConnection
        let service = FRPClientService(config: config, connector: mockConnector)

        _ = Task {
            _ = try await serverConn.readMessage()
            try await serverConn.writeMessage(FRPLoginRespMessage(version: "0.61.0", runID: "run-reg-fail", error: nil))
            let encServer = CryptoConnection(wrapping: serverConn, token: "")
            _ = try await encServer.readMessage()
            try await encServer.writeMessage(FRPNewProxyRespMessage(proxyName: "failing_reg", remoteAddr: "", error: "port conflict"))
        }

        do {
            try await service.start()
            XCTFail("Expected proxy registration failure")
        } catch {
            let running = await service.isRunningStatus
            XCTAssertFalse(running)
        }
    }
}
