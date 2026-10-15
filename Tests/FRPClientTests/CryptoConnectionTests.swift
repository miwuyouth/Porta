import XCTest
@testable import FRPClient

final class CryptoConnectionTests: XCTestCase {
    func testEndToEndCryptoBidirectionalTransfer() async throws {
        let (pipeA, pipeB) = MockPipeConnection.createPair()
        let token = "test_secret_token_123"

        let clientCrypto = CryptoConnection(wrapping: pipeA, token: token)
        let serverCrypto = CryptoConnection(wrapping: pipeB, token: token)

        let originalData = Data("Hello, Encrypted FRP World!".utf8)

        // Write from client to server
        try await clientCrypto.write(originalData)
        let receivedByServer = try await serverCrypto.read(exactCount: originalData.count)
        XCTAssertEqual(receivedByServer, originalData)

        // Echo back from server to client
        let responseData = Data("Server Response: 200 OK".utf8)
        try await serverCrypto.write(responseData)
        let receivedByClient = try await clientCrypto.read(exactCount: responseData.count)
        XCTAssertEqual(receivedByClient, responseData)

        clientCrypto.close()
        serverCrypto.close()
    }

    func testLargePayloadTransfer() async throws {
        let (pipeA, pipeB) = MockPipeConnection.createPair()
        let token = "large_payload_token"

        let clientCrypto = CryptoConnection(wrapping: pipeA, token: token)
        let serverCrypto = CryptoConnection(wrapping: pipeB, token: token)

        let largeData = Data(repeating: 0x42, count: 64 * 1024) // 64 KB

        try await clientCrypto.write(largeData)
        let received = try await serverCrypto.read(exactCount: largeData.count)
        XCTAssertEqual(received, largeData)

        clientCrypto.close()
        serverCrypto.close()
    }

    func testConcurrentWritesAreSerialized() async throws {
        let (pipeA, pipeB) = MockPipeConnection.createPair()
        let token = "concurrency_token"

        let clientCrypto = CryptoConnection(wrapping: pipeA, token: token)
        let serverCrypto = CryptoConnection(wrapping: pipeB, token: token)

        // Send 10 messages sequentially verified
        let messages = (0..<10).map { "Message \($0)\n" }
        for msg in messages {
            let data = Data(msg.utf8)
            try await clientCrypto.write(data)
            let received = try await serverCrypto.read(exactCount: data.count)
            XCTAssertEqual(received, data)
        }

        clientCrypto.close()
        serverCrypto.close()
    }
}
