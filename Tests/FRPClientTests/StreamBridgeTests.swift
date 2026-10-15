import XCTest
@testable import FRPClient

final class StreamBridgeTests: XCTestCase {
    func testBidirectionalStreamBridge() async throws {
        // (clientWorkConn, serverWorkConn)
        let (clientWorkConn, serverWorkConn) = MockPipeConnection.createPair()
        // (clientLocalConn, serviceConn)
        let (clientLocalConn, serviceConn) = MockPipeConnection.createPair()

        // Start bridge: bridges clientWorkConn <-> clientLocalConn
        let bridgeTask = Task {
            await StreamBridge.bridge(clientWorkConn, clientLocalConn)
        }

        // Test 1: Service writes to clientLocalConn -> should appear at serverWorkConn
        let testMessage1 = Data("Hello from Local Service".utf8)
        try await serviceConn.write(testMessage1)

        let receivedAtServer = try await serverWorkConn.read(exactCount: testMessage1.count)
        XCTAssertEqual(receivedAtServer, testMessage1)

        // Test 2: Server writes to clientWorkConn -> should appear at serviceConn
        let testMessage2 = Data("Hello from Remote Client".utf8)
        try await serverWorkConn.write(testMessage2)

        let receivedAtService = try await serviceConn.read(exactCount: testMessage2.count)
        XCTAssertEqual(receivedAtService, testMessage2)

        // Close service side -> bridge should close both and terminate
        serviceConn.close()
        _ = await bridgeTask.result

        XCTAssertTrue(clientWorkConn.isClosed)
        XCTAssertTrue(clientLocalConn.isClosed)
    }

    func testLargePayloadTransfer() async throws {
        let (clientWorkConn, serverWorkConn) = MockPipeConnection.createPair()
        let (clientLocalConn, serviceConn) = MockPipeConnection.createPair()

        let bridgeTask = Task {
            await StreamBridge.bridge(clientWorkConn, clientLocalConn)
        }

        // 256KB random bytes
        var largeData = Data(count: 256 * 1024)
        for i in 0..<largeData.count {
            largeData[i] = UInt8(i % 256)
        }

        try await serviceConn.write(largeData)
        let received = try await serverWorkConn.read(exactCount: largeData.count)
        XCTAssertEqual(received, largeData)

        serviceConn.close()
        _ = await bridgeTask.result
    }

    func testWorkConnectionClosePropagatesToLocalConnection() async throws {
        let (clientWorkConn, serverWorkConn) = MockPipeConnection.createPair()
        let (clientLocalConn, _) = MockPipeConnection.createPair()

        let bridgeTask = Task {
            await StreamBridge.bridge(clientWorkConn, clientLocalConn)
        }

        // Server closes work connection
        serverWorkConn.close()
        _ = await bridgeTask.result

        // Both bridge legs should be closed
        XCTAssertTrue(clientWorkConn.isClosed)
        XCTAssertTrue(clientLocalConn.isClosed)
    }
}
