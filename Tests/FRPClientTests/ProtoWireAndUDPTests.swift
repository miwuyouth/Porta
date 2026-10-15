import XCTest
@testable import FRPClient

final class ProtoWireAndUDPTests: XCTestCase {

    func testUDPPacketHeaderEncodeDecode() throws {
        let payload = Data("DNS query payload".utf8)
        let pkt = UDPPacket(proxyName: "udp-dns", seq: 1001, payload: payload)

        let encoded = try UDPPacketCodec.encode(pkt)
        let decoded = try UDPPacketCodec.decode(encoded)

        XCTAssertEqual(decoded.proxyName, "udp-dns")
        XCTAssertEqual(decoded.seq, 1001)
        XCTAssertEqual(decoded.payload, payload)
    }

    func testUDPPacketPayloadSlicing() {
        let payload = Data(repeating: 0xAA, count: 2500)
        let chunks = UDPPacketCodec.slicePayload(payload, maxChunkSize: 1000)

        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].count, 1000)
        XCTAssertEqual(chunks[1].count, 1000)
        XCTAssertEqual(chunks[2].count, 500)
    }

    func testUDPPacketReassembly() {
        let c1 = Data([1, 2, 3])
        let c2 = Data([4, 5])
        let c3 = Data([6, 7, 8, 9])

        let reassembled = UDPPacketCodec.reassembleChunks([c1, c2, c3])
        XCTAssertEqual(reassembled, Data([1, 2, 3, 4, 5, 6, 7, 8, 9]))
    }

    func testUDPPacketCorruptHeaderDetection() {
        let tooShort = Data([0, 5]) // less than 10 bytes
        XCTAssertThrowsError(try UDPPacketCodec.decode(tooShort)) { error in
            XCTAssertEqual(error as? UDPPacketCodecError, .headerTooShort)
        }

        // declared proxyName length = 50, but packet total is only 12 bytes
        var corrupt = Data([0, 50])
        corrupt.append(contentsOf: [UInt8](repeating: 0, count: 10))
        XCTAssertThrowsError(try UDPPacketCodec.decode(corrupt)) { error in
            XCTAssertEqual(error as? UDPPacketCodecError, .corruptHeader)
        }
    }

    func testUDPPacketZeroPayload() throws {
        let pkt = UDPPacket(proxyName: "ping", seq: 1, payload: Data())
        let encoded = try UDPPacketCodec.encode(pkt)
        let decoded = try UDPPacketCodec.decode(encoded)

        XCTAssertEqual(decoded.proxyName, "ping")
        XCTAssertEqual(decoded.seq, 1)
        XCTAssertTrue(decoded.payload.isEmpty)
    }

    func testWireFramingWriteAndReadPacket() throws {
        let pkt = UDPPacket(proxyName: "echo", seq: 55, payload: Data([0x01, 0x02, 0x03]))
        let encoded = try UDPPacketCodec.encode(pkt)
        let decoded = try UDPPacketCodec.decode(encoded)
        XCTAssertEqual(decoded.proxyName, "echo")
        XCTAssertEqual(decoded.payload.count, 3)
    }

    func testWireFramingBufferPoolReuse() {
        let pool = BufferPool(capacity: 1024)
        XCTAssertEqual(pool.availableCount, 0)

        let buf = pool.acquire()
        XCTAssertEqual(buf.count, 0)

        pool.release(buf)
        XCTAssertEqual(pool.availableCount, 1)

        let reusedBuf = pool.acquire()
        XCTAssertEqual(pool.availableCount, 0)
        XCTAssertEqual(reusedBuf.count, 0)
    }

    func testWireFramingMaxPacketSizeLimit() {
        let oversized = Data(repeating: 0xFF, count: UDPPacketCodec.maxUDPPacketSize + 1)
        let pkt = UDPPacket(proxyName: "huge", seq: 9, payload: oversized)
        XCTAssertThrowsError(try UDPPacketCodec.encode(pkt)) { error in
            XCTAssertEqual(error as? UDPPacketCodecError, .payloadTooLarge)
        }
    }

    func testUDPPacketChannelMultiplexing() throws {
        let p1 = UDPPacket(proxyName: "service-a", seq: 1, payload: Data("msg-a".utf8))
        let p2 = UDPPacket(proxyName: "service-b", seq: 2, payload: Data("msg-b".utf8))

        let d1 = try UDPPacketCodec.decode(try UDPPacketCodec.encode(p1))
        let d2 = try UDPPacketCodec.decode(try UDPPacketCodec.encode(p2))

        XCTAssertNotEqual(d1.proxyName, d2.proxyName)
        XCTAssertEqual(d1.proxyName, "service-a")
        XCTAssertEqual(d2.proxyName, "service-b")
    }

    func testUDPPacketSequenceValidation() {
        var seq: UInt64 = 0
        var packets: [UDPPacket] = []
        for i in 0..<5 {
            seq += 1
            packets.append(UDPPacket(proxyName: "stream", seq: seq, payload: Data([UInt8(i)])))
        }

        for i in 0..<packets.count {
            XCTAssertEqual(packets[i].seq, UInt64(i + 1))
        }
    }
}
