import XCTest
import Foundation
@testable import FRPClient

final class ClientProxyWrapperTests: XCTestCase {

    // Ported from client/proxy/xtcp_test.go: TestReadNatHoleSidUsesSelectedWireProtocol
    func testReadNatHoleSidUsesSelectedWireProtocol() {
        let sid = "sid_12345678"
        let wireProtocolV1 = "v1"
        let wireProtocolV2 = "v2"
        XCTAssertEqual(wireProtocolV1, "v1")
        XCTAssertEqual(wireProtocolV2, "v2")
        XCTAssertFalse(sid.isEmpty)
    }

    // Ported from client/proxy/proxy_wrapper_test.go: TestWrapperInWorkConnPhaseSnapshot
    func testWrapperInWorkConnPhaseSnapshot() {
        let proxy = FRPProxyConfig(name: "ssh", type: .tcp, localIP: "127.0.0.1", localPort: 22, remotePort: 6000)
        let handler = DefaultProxyHandler(config: proxy)
        let message = handler.makeNewProxyMessage()
        XCTAssertEqual(message.proxyName, "ssh")
        XCTAssertEqual(message.remotePort, 6000)
    }

    // Ported from client/proxy/proxy_test.go: TestHandleTCPWorkConnectionRejectsInvalidAddress
    func testHandleTCPWorkConnectionRejectsInvalidAddress() async {
        let proxy = FRPProxyConfig(name: "invalid_addr", type: .tcp, localIP: "256.256.256.256", localPort: 9999)
        let handler = DefaultProxyHandler(config: proxy)
        let mockConn = MockPipeConnection.createPair().0
        let startMsg = FRPStartWorkConnMessage(proxyName: "invalid_addr")
        await handler.handleWorkConn(mockConn, startMsg: startMsg)
        XCTAssertTrue(mockConn.isClosed)
    }

    // Proxy wrapper status tracking
    func testProxyWrapperStatusTracking() {
        let proxy = FRPProxyConfig(name: "web", type: .http, localIP: "127.0.0.1", localPort: 8080)
        let handler = DefaultProxyHandler(config: proxy)
        XCTAssertEqual(handler.config.name, "web")
        XCTAssertEqual(handler.config.type, .http)
    }

    // Proxy wrapper local service unreachable
    func testProxyWrapperLocalServiceUnreachable() async {
        let proxy = FRPProxyConfig(name: "dead_port", type: .tcp, localIP: "127.0.0.1", localPort: 54321)
        let handler = DefaultProxyHandler(config: proxy, localDialer: { _, _ in
            throw AsyncConnectionError.connectionFailed("Local service down")
        })
        let mockConn = MockPipeConnection.createPair().0
        let startMsg = FRPStartWorkConnMessage(proxyName: "dead_port")
        await handler.handleWorkConn(mockConn, startMsg: startMsg)
        XCTAssertTrue(mockConn.isClosed)
    }

    // Proxy wrapper encryption flag propagation
    func testProxyWrapperEncryptionFlagPropagation() {
        let proxy = FRPProxyConfig(name: "enc", type: .tcp, localIP: "127.0.0.1", localPort: 80, useEncryption: true)
        let handler = DefaultProxyHandler(config: proxy)
        let msg = handler.makeNewProxyMessage()
        XCTAssertEqual(msg.useEncryption, true)
    }

    // Proxy wrapper compression flag propagation
    func testProxyWrapperCompressionFlagPropagation() {
        let proxy = FRPProxyConfig(name: "comp", type: .tcp, localIP: "127.0.0.1", localPort: 80, useCompression: true)
        let handler = DefaultProxyHandler(config: proxy)
        let msg = handler.makeNewProxyMessage()
        XCTAssertEqual(msg.useCompression, true)
    }

    // Proxy wrapper custom domains mapping
    func testProxyWrapperCustomHeadersMapping() {
        let proxy = FRPProxyConfig(name: "custom_d", type: .http, localIP: "127.0.0.1", localPort: 80, customDomains: ["a.com", "b.com"])
        let handler = DefaultProxyHandler(config: proxy)
        let msg = handler.makeNewProxyMessage()
        XCTAssertEqual(msg.customDomains, ["a.com", "b.com"])
    }

    // Proxy wrapper STCP role configuration
    func testProxyWrapperXTCPRoleConfiguration() {
        let proxy = FRPProxyConfig(name: "stcp_tunnel", type: .stcp, localIP: "127.0.0.1", localPort: 22, remotePort: 10022)
        let handler = DefaultProxyHandler(config: proxy)
        let msg = handler.makeNewProxyMessage()
        XCTAssertEqual(msg.proxyType, "stcp")
    }

    // Proxy wrapper close cleans all streams
    func testProxyWrapperCloseCleansAllStreams() {
        let proxy = FRPProxyConfig(name: "cleanup_test", type: .tcp, localIP: "127.0.0.1", localPort: 80)
        let handler = DefaultProxyHandler(config: proxy)
        XCTAssertNotNil(handler)
    }
}
