import XCTest
@testable import FRPClient

final class ProxyHandlerTests: XCTestCase {
    func testTCPProxyMessageMapping() {
        let config = FRPProxyConfig(
            name: "ssh_proxy",
            type: .tcp,
            localIP: "127.0.0.1",
            localPort: 22,
            remotePort: 6000,
            useEncryption: true,
            useCompression: true
        )
        let handler = DefaultProxyHandler(config: config)
        let msg = handler.makeNewProxyMessage()

        XCTAssertEqual(msg.proxyName, "ssh_proxy")
        XCTAssertEqual(msg.proxyType, "tcp")
        XCTAssertEqual(msg.remotePort, 6000)
        XCTAssertEqual(msg.useEncryption, true)
        XCTAssertEqual(msg.useCompression, true)
    }

    func testHTTPProxyMessageMapping() {
        let config = FRPProxyConfig(
            name: "web_proxy",
            type: .http,
            localIP: "127.0.0.1",
            localPort: 8080,
            customDomains: ["example.com", "app.example.com"],
            subdomain: "blog",
            locations: ["/api", "/v1"],
            hostHeaderRewrite: "local.backend",
            httpUser: "user",
            httpPassword: "pwd"
        )
        let handler = DefaultProxyHandler(config: config)
        let msg = handler.makeNewProxyMessage()

        XCTAssertEqual(msg.proxyName, "web_proxy")
        XCTAssertEqual(msg.proxyType, "http")
        XCTAssertEqual(msg.customDomains, ["example.com", "app.example.com"])
        XCTAssertEqual(msg.subdomain, "blog")
        XCTAssertEqual(msg.locations, ["/api", "/v1"])
        XCTAssertEqual(msg.hostHeaderRewrite, "local.backend")
        XCTAssertEqual(msg.httpUser, "user")
        XCTAssertEqual(msg.httpPwd, "pwd")
    }

    func testHTTPSProxyMessageMapping() {
        let config = FRPProxyConfig(
            name: "secure_web",
            type: .https,
            localIP: "127.0.0.1",
            localPort: 8443,
            customDomains: ["secure.example.com"]
        )
        let handler = DefaultProxyHandler(config: config)
        let msg = handler.makeNewProxyMessage()

        XCTAssertEqual(msg.proxyName, "secure_web")
        XCTAssertEqual(msg.proxyType, "https")
        XCTAssertEqual(msg.customDomains, ["secure.example.com"])
    }

    func testSTCPProxyMessageMapping() {
        let config = FRPProxyConfig(
            name: "secret_ssh",
            type: .stcp,
            localIP: "127.0.0.1",
            localPort: 22,
            secretKey: "stcp_secret_token"
        )
        let handler = DefaultProxyHandler(config: config)
        let msg = handler.makeNewProxyMessage()

        XCTAssertEqual(msg.proxyName, "secret_ssh")
        XCTAssertEqual(msg.proxyType, "stcp")
        XCTAssertEqual(msg.sk, "stcp_secret_token")
    }

    func testTCPMuxProxyMessageMapping() {
        let config = FRPProxyConfig(
            name: "tcpmux_service",
            type: .tcpmux,
            localIP: "127.0.0.1",
            localPort: 3306
        )
        let handler = DefaultProxyHandler(config: config)
        let msg = handler.makeNewProxyMessage()

        XCTAssertEqual(msg.proxyName, "tcpmux_service")
        XCTAssertEqual(msg.proxyType, "tcpmux")
        XCTAssertEqual(msg.multiplexer, "httpconnect")
    }

    func testHandleWorkConnWithLocalDialerSuccess() async throws {
        let config = FRPProxyConfig(
            name: "echo_proxy",
            type: .tcp,
            localIP: "127.0.0.1",
            localPort: 9999
        )

        // Mock local service
        let (localClient, localServer) = MockPipeConnection.createPair()

        let handler = DefaultProxyHandler(config: config, localDialer: { _, _ in
            return localClient
        })

        // Mock work connection from frps
        let (workClient, workServer) = MockPipeConnection.createPair()

        let startMsg = FRPStartWorkConnMessage(proxyName: "echo_proxy")
        Task {
            await handler.handleWorkConn(workClient, startMsg: startMsg)
        }

        // Test proxy traffic: Server sends through workConn -> localServer receives
        let testData = Data("PING_TEST".utf8)
        try await workServer.write(testData)

        let receivedAtLocal = try await localServer.read(exactCount: testData.count)
        XCTAssertEqual(receivedAtLocal, testData)

        // Local responds -> Server receives through workConn
        let replyData = Data("PONG_TEST".utf8)
        try await localServer.write(replyData)

        let receivedAtServer = try await workServer.read(exactCount: replyData.count)
        XCTAssertEqual(receivedAtServer, replyData)

        workServer.close()
    }

    func testHandleWorkConnLocalConnectFailureClosesWorkConn() async throws {
        let config = FRPProxyConfig(
            name: "failing_proxy",
            type: .tcp,
            localIP: "127.0.0.1",
            localPort: 9999
        )

        let handler = DefaultProxyHandler(config: config, localDialer: { _, _ in
            throw AsyncConnectionError.connectionFailed("Local service down")
        })

        let (workClient, _) = MockPipeConnection.createPair()
        let startMsg = FRPStartWorkConnMessage(proxyName: "failing_proxy")

        await handler.handleWorkConn(workClient, startMsg: startMsg)

        // Work connection must be closed immediately on failure
        XCTAssertTrue(workClient.isClosed)
    }
}
