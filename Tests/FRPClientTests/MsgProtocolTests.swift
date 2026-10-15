import XCTest
@testable import FRPClient

final class MsgProtocolTests: XCTestCase {

    func testLoginMessageSerialization() throws {
        let login = FRPLoginMessage(
            version: "0.61.0",
            hostname: "mac-host",
            os: "darwin",
            arch: "arm64",
            user: "test_user",
            privilegeKey: "priv_key_123",
            timestamp: 1700000000,
            runID: "run-001",
            metas: ["tag": "prod"],
            poolCount: 5
        )
        let frame = try FRPFrameCodec.encode(login)
        XCTAssertEqual(frame[0], FRPMessageType.login.rawValue)

        let header = try FRPFrameCodec.decodeHeader(Data(frame.prefix(9)))
        XCTAssertEqual(header.type, .login)
        XCTAssertEqual(Int(header.length), frame.count - 9)

        let decoded = try FRPFrameCodec.decodePayload(type: .login, payload: Data(frame.dropFirst(9))) as? FRPLoginMessage
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.user, "test_user")
        XCTAssertEqual(decoded?.runID, "run-001")
        XCTAssertEqual(decoded?.poolCount, 5)
        XCTAssertEqual(decoded?.metas?["tag"], "prod")
    }

    func testLoginRespMessageSerialization() throws {
        let resp = FRPLoginRespMessage(version: "0.61.0", runID: "run-resp-999", error: nil)
        let frame = try FRPFrameCodec.encode(resp)
        let header = try FRPFrameCodec.decodeHeader(Data(frame.prefix(9)))
        XCTAssertEqual(header.type, .loginResp)

        let decoded = try FRPFrameCodec.decodePayload(type: .loginResp, payload: Data(frame.dropFirst(9))) as? FRPLoginRespMessage
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.runID, "run-resp-999")
        XCTAssertNil(decoded?.error)
    }

    func testNewProxyMessageSerializationTCP() throws {
        let msg = FRPNewProxyMessage(
            proxyName: "tcp-proxy-1",
            proxyType: "tcp",
            useEncryption: true,
            useCompression: false,
            remotePort: 8080
        )
        let frame = try FRPFrameCodec.encode(msg)
        let decoded = try FRPFrameCodec.decodePayload(type: .newProxy, payload: Data(frame.dropFirst(9))) as? FRPNewProxyMessage
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.proxyName, "tcp-proxy-1")
        XCTAssertEqual(decoded?.proxyType, "tcp")
        XCTAssertEqual(decoded?.remotePort, 8080)
        XCTAssertEqual(decoded?.useEncryption, true)
    }

    func testNewProxyMessageSerializationHTTP() throws {
        let msg = FRPNewProxyMessage(
            proxyName: "web-proxy",
            proxyType: "http",
            customDomains: ["example.com", "api.example.com"],
            subdomain: "test",
            locations: ["/static", "/v1"]
        )
        let frame = try FRPFrameCodec.encode(msg)
        let decoded = try FRPFrameCodec.decodePayload(type: .newProxy, payload: Data(frame.dropFirst(9))) as? FRPNewProxyMessage
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.proxyName, "web-proxy")
        XCTAssertEqual(decoded?.proxyType, "http")
        XCTAssertEqual(decoded?.customDomains, ["example.com", "api.example.com"])
        XCTAssertEqual(decoded?.subdomain, "test")
        XCTAssertEqual(decoded?.locations, ["/static", "/v1"])
    }

    func testNewProxyMessageSerializationSTCP() throws {
        let msg = FRPNewProxyMessage(
            proxyName: "secret-tunnel",
            proxyType: "stcp",
            sk: "p@ssw0rd123"
        )
        let frame = try FRPFrameCodec.encode(msg)
        let decoded = try FRPFrameCodec.decodePayload(type: .newProxy, payload: Data(frame.dropFirst(9))) as? FRPNewProxyMessage
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.proxyName, "secret-tunnel")
        XCTAssertEqual(decoded?.proxyType, "stcp")
        XCTAssertEqual(decoded?.sk, "p@ssw0rd123")
    }

    func testNewProxyRespMessageSerialization() throws {
        let resp = FRPNewProxyRespMessage(proxyName: "web-proxy", remoteAddr: "0.0.0.0:8080", error: nil)
        let frame = try FRPFrameCodec.encode(resp)
        let decoded = try FRPFrameCodec.decodePayload(type: .newProxyResp, payload: Data(frame.dropFirst(9))) as? FRPNewProxyRespMessage
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.proxyName, "web-proxy")
        XCTAssertEqual(decoded?.remoteAddr, "0.0.0.0:8080")
        XCTAssertNil(decoded?.error)
    }

    func testCloseProxyMessageSerialization() throws {
        let msg = FRPCloseProxyMessage(proxyName: "old-proxy")
        let frame = try FRPFrameCodec.encode(msg)
        let decoded = try FRPFrameCodec.decodePayload(type: .closeProxy, payload: Data(frame.dropFirst(9))) as? FRPCloseProxyMessage
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.proxyName, "old-proxy")
    }

    func testReqWorkConnMessageSerialization() throws {
        let msg = FRPReqWorkConnMessage()
        let frame = try FRPFrameCodec.encode(msg)
        let decoded = try FRPFrameCodec.decodePayload(type: .reqWorkConn, payload: Data(frame.dropFirst(9))) as? FRPReqWorkConnMessage
        XCTAssertNotNil(decoded)
    }

    func testNewWorkConnMessageSerialization() throws {
        let msg = FRPNewWorkConnMessage(runID: "run-work-123", privilegeKey: "key-hash", timestamp: 1700000001)
        let frame = try FRPFrameCodec.encode(msg)
        let decoded = try FRPFrameCodec.decodePayload(type: .newWorkConn, payload: Data(frame.dropFirst(9))) as? FRPNewWorkConnMessage
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.runID, "run-work-123")
        XCTAssertEqual(decoded?.privilegeKey, "key-hash")
        XCTAssertEqual(decoded?.timestamp, 1700000001)
    }

    func testStartWorkConnMessageSerialization() throws {
        let msg = FRPStartWorkConnMessage(
            proxyName: "target-service",
            srcAddr: "192.168.1.10",
            dstAddr: "10.0.0.1",
            srcPort: 54321,
            dstPort: 80,
            error: nil
        )
        let frame = try FRPFrameCodec.encode(msg)
        let decoded = try FRPFrameCodec.decodePayload(type: .startWorkConn, payload: Data(frame.dropFirst(9))) as? FRPStartWorkConnMessage
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.proxyName, "target-service")
        XCTAssertEqual(decoded?.srcAddr, "192.168.1.10")
        XCTAssertEqual(decoded?.srcPort, 54321)
        XCTAssertEqual(decoded?.dstPort, 80)
    }

    func testPingMessageSerialization() throws {
        let msg = FRPPingMessage(privilegeKey: "ping-key", timestamp: 123456789)
        let frame = try FRPFrameCodec.encode(msg)
        let decoded = try FRPFrameCodec.decodePayload(type: .ping, payload: Data(frame.dropFirst(9))) as? FRPPingMessage
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.privilegeKey, "ping-key")
        XCTAssertEqual(decoded?.timestamp, 123456789)
    }

    func testPongMessageSerialization() throws {
        let msg = FRPPongMessage(error: "heartbeat rejected")
        let frame = try FRPFrameCodec.encode(msg)
        let decoded = try FRPFrameCodec.decodePayload(type: .pong, payload: Data(frame.dropFirst(9))) as? FRPPongMessage
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.error, "heartbeat rejected")
    }

    func testNatHoleSidMessageSerialization() throws {
        let msg = FRPNatHoleSidMessage(sid: "nat-sid-98765")
        let frame = try FRPFrameCodec.encode(msg)
        let decoded = try FRPFrameCodec.decodePayload(type: .natHoleSid, payload: Data(frame.dropFirst(9))) as? FRPNatHoleSidMessage
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.sid, "nat-sid-98765")
    }

    func testNatHoleClientMessageSerialization() throws {
        let msg = FRPNatHoleClientMessage(sid: "sid-001", proxyName: "p2p-proxy")
        let frame = try FRPFrameCodec.encode(msg)
        let decoded = try FRPFrameCodec.decodePayload(type: .natHoleClient, payload: Data(frame.dropFirst(9))) as? FRPNatHoleClientMessage
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.sid, "sid-001")
        XCTAssertEqual(decoded?.proxyName, "p2p-proxy")
    }

    func testNatHoleRespMessageSerialization() throws {
        let msg = FRPNatHoleRespMessage(
            sid: "sid-002",
            visitorCandidateAddress: ["1.1.1.1:12345"],
            clientCandidateAddress: ["2.2.2.2:54321"],
            error: nil
        )
        let frame = try FRPFrameCodec.encode(msg)
        let decoded = try FRPFrameCodec.decodePayload(type: .natHoleResp, payload: Data(frame.dropFirst(9))) as? FRPNatHoleRespMessage
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.sid, "sid-002")
        XCTAssertEqual(decoded?.visitorCandidateAddress, ["1.1.1.1:12345"])
        XCTAssertEqual(decoded?.clientCandidateAddress, ["2.2.2.2:54321"])
    }

    func testNatHoleReportMessageSerialization() throws {
        let msg = FRPNatHoleReportMessage(sid: "sid-003", candidateAddress: ["10.0.0.5:9000", "192.168.1.50:9000"])
        let frame = try FRPFrameCodec.encode(msg)
        let decoded = try FRPFrameCodec.decodePayload(type: .natHoleReport, payload: Data(frame.dropFirst(9))) as? FRPNatHoleReportMessage
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.sid, "sid-003")
        XCTAssertEqual(decoded?.candidateAddress.count, 2)
    }

    func testUDPPacketMessageSerialization() throws {
        let msg = FRPUDPPacketMessage(proxyName: "udp-dns", content: "dGVzdC1kYXRh", seq: 42)
        let frame = try FRPFrameCodec.encode(msg)
        let decoded = try FRPFrameCodec.decodePayload(type: .udpPacket, payload: Data(frame.dropFirst(9))) as? FRPUDPPacketMessage
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.proxyName, "udp-dns")
        XCTAssertEqual(decoded?.content, "dGVzdC1kYXRh")
        XCTAssertEqual(decoded?.seq, 42)
    }

    func testFrameCodecHeaderBigEndianEncoding() throws {
        var header = Data()
        header.append(FRPMessageType.ping.rawValue)
        let length: Int64 = 0x0102030405060708
        var bigLen = length.bigEndian
        withUnsafeBytes(of: &bigLen) { header.append(contentsOf: $0) }

        XCTAssertEqual(header.count, 9)
        // Check byte 1 to 8 sequence matches big endian bytes
        XCTAssertEqual(header[1], 0x01)
        XCTAssertEqual(header[2], 0x02)
        XCTAssertEqual(header[8], 0x08)
    }

    func testFrameCodecOversizedPayloadRejection() {
        let header = Data([FRPMessageType.login.rawValue])
        let length: Int64 = 20 * 1024 * 1024 // 20MB > 10MB limit
        var bigLen = length.bigEndian
        var fullHeader = header
        withUnsafeBytes(of: &bigLen) { fullHeader.append(contentsOf: $0) }

        XCTAssertThrowsError(try FRPFrameCodec.decodeHeader(fullHeader)) { error in
            guard case FRPFrameError.invalidLength(let len) = error else {
                XCTFail("Expected invalidLength error, got: \(error)")
                return
            }
            XCTAssertEqual(len, length)
        }
    }

    func testFrameCodecCorruptJSONHandling() {
        let corruptData = Data("{\"unclosed_json: true".utf8)
        XCTAssertThrowsError(try FRPFrameCodec.decodePayload(type: .login, payload: corruptData)) { error in
            guard case FRPFrameError.decodingError = error else {
                XCTFail("Expected decodingError, got: \(error)")
                return
            }
        }
    }

    func testFrameCodecUnknownMessageTypeHandling() {
        let header = Data([0xFE, 0, 0, 0, 0, 0, 0, 0, 5])
        XCTAssertThrowsError(try FRPFrameCodec.decodeHeader(header)) { error in
            guard case FRPFrameError.unsupportedMessageType(let code) = error else {
                XCTFail("Expected unsupportedMessageType, got: \(error)")
                return
            }
            XCTAssertEqual(code, 0xFE)
        }
    }

    func testFrameCodecTruncatedHeaderHandling() {
        let truncated = Data([0x6f, 0, 0, 0]) // only 4 bytes instead of 9
        XCTAssertThrowsError(try FRPFrameCodec.decodeHeader(truncated)) { error in
            guard case FRPFrameError.unexpectedEOF = error else {
                XCTFail("Expected unexpectedEOF, got: \(error)")
                return
            }
        }
    }
}
