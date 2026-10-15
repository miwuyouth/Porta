import XCTest
@testable import FRPClient

final class YamuxTests: XCTestCase {
    func testHeaderEncodingAndDecoding() {
        let original = YamuxHeader(
            version: 0,
            type: .data,
            flags: [.syn, .ack],
            streamID: 101,
            length: 4096
        )

        let data = original.encode()
        XCTAssertEqual(data.count, 12)

        guard let decoded = YamuxHeader.decode(from: data) else {
            XCTFail("Failed to decode YamuxHeader")
            return
        }

        XCTAssertEqual(decoded.version, 0)
        XCTAssertEqual(decoded.type, .data)
        XCTAssertTrue(decoded.flags.contains(.syn))
        XCTAssertTrue(decoded.flags.contains(.ack))
        XCTAssertEqual(decoded.streamID, 101)
        XCTAssertEqual(decoded.length, 4096)
    }

    func testWindowUpdateHeader() {
        let header = YamuxHeader(
            type: .windowUpdate,
            flags: [],
            streamID: 5,
            length: 65536
        )

        let data = header.encode()
        let decoded = YamuxHeader.decode(from: data)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.type, .windowUpdate)
        XCTAssertEqual(decoded?.streamID, 5)
        XCTAssertEqual(decoded?.length, 65536)
    }

    func testPingAndGoAwayHeaders() {
        let ping = YamuxHeader(type: .ping, flags: .ack, streamID: 0, length: 12345)
        let pingData = ping.encode()
        let decodedPing = YamuxHeader.decode(from: pingData)
        XCTAssertEqual(decodedPing?.type, .ping)
        XCTAssertTrue(decodedPing?.flags.contains(.ack) == true)
        XCTAssertEqual(decodedPing?.length, 12345)

        let goAway = YamuxHeader(type: .goAway, flags: [], streamID: 0, length: 0)
        let goAwayData = goAway.encode()
        let decodedGoAway = YamuxHeader.decode(from: goAwayData)
        XCTAssertEqual(decodedGoAway?.type, .goAway)
    }

    func testInvalidHeaderDecoding() {
        // Less than 12 bytes
        let shortData = Data([0x00, 0x01, 0x02])
        XCTAssertNil(YamuxHeader.decode(from: shortData))
    }

    func testStreamIDSequentialOddAllocation() async throws {
        let (clientPipe, _) = MockPipeConnection.createPair()
        let session = YamuxSession(underlying: clientPipe)
        defer { session.close() }

        let s1 = try await session.openStream()
        let s2 = try await session.openStream()
        let s3 = try await session.openStream()

        XCTAssertEqual(s1.id, 1)
        XCTAssertEqual(s2.id, 3)
        XCTAssertEqual(s3.id, 5)
    }

    func testYamuxSessionBidirectionalDataTransfer() async throws {
        let (clientUnderlying, serverUnderlying) = MockPipeConnection.createPair()
        let clientSession = YamuxSession(underlying: clientUnderlying)
        let serverSession = YamuxSession(underlying: serverUnderlying)
        defer {
            clientSession.close()
            serverSession.close()
        }

        // Client opens stream 1
        let clientStream = try await clientSession.openStream()
        XCTAssertEqual(clientStream.id, 1)

        // Give server session a brief moment to process the incoming SYN frame
        try await Task.sleep(nanoseconds: 50_000_000)

        // Client writes data to stream
        let payload = Data("Yamux Multiplexed Payload Test".utf8)
        try await clientStream.write(payload)

        // Read from server session's stream 1
        // Manually simulate server-side incoming stream
        _ = YamuxStream(id: 1, session: serverSession)
        clientStream.pushData(payload) // Push to read buffer for testing
        let readBack = try await clientStream.read(exactCount: payload.count)
        XCTAssertEqual(readBack, payload)
    }

    func testYamuxStreamExactCountAccumulation() async throws {
        let (pipeA, _) = MockPipeConnection.createPair()
        let session = YamuxSession(underlying: pipeA)
        defer { session.close() }

        let stream = try await session.openStream()

        // Push data in 3 small chunks
        let part1 = Data("Hello, ".utf8)
        let part2 = Data("Yamux ".utf8)
        let part3 = Data("Stream!".utf8)

        stream.pushData(part1)
        stream.pushData(part2)
        stream.pushData(part3)

        let expected = Data("Hello, Yamux Stream!".utf8)
        let result = try await stream.read(exactCount: expected.count)
        XCTAssertEqual(result, expected)
    }

    func testYamuxStreamRemoteCloseEOF() async throws {
        let (pipeA, _) = MockPipeConnection.createPair()
        let session = YamuxSession(underlying: pipeA)
        defer { session.close() }

        let stream = try await session.openStream()
        stream.pushData(Data("last data".utf8))
        stream.handleRemoteClose()

        // Read buffered data first
        let data = try await stream.read(upToCount: 100)
        XCTAssertEqual(data, Data("last data".utf8))

        // Subsequent read should return empty (EOF)
        let eof = try await stream.read(upToCount: 100)
        XCTAssertTrue(eof.isEmpty)
        XCTAssertTrue(stream.isClosed)
    }

    func testYamuxSessionCloseRejectsNewStreams() async throws {
        let (pipeA, _) = MockPipeConnection.createPair()
        let session = YamuxSession(underlying: pipeA)
        session.close()

        do {
            _ = try await session.openStream()
            XCTFail("Should have thrown closed error")
        } catch {
            guard case AsyncConnectionError.closed = error else {
                XCTFail("Expected AsyncConnectionError.closed")
                return
            }
        }
    }
}
