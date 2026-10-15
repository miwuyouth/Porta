import XCTest
@testable import FRPClient

final class FrameCodecTests: XCTestCase {
    func testEncodeAndDecodeLoginMessage() throws {
        let login = FRPLoginMessage(
            version: "0.61.0",
            hostname: "my-mac",
            os: "darwin",
            arch: "arm64",
            user: "alice",
            privilegeKey: "abcd1234ef567890",
            timestamp: 123456789,
            runID: "run-001",
            metas: ["client_version": "1.0.0"],
            clientSpec: FRPClientSpec(type: "test", alwaysAuthPass: true),
            poolCount: 5
        )

        let frameData = try FRPFrameCodec.encode(login)

        // 1. Verify header size and type byte
        XCTAssertGreaterThanOrEqual(frameData.count, 9)
        XCTAssertEqual(frameData[0], FRPMessageType.login.rawValue)

        // 2. Extract Big-Endian length
        let header = try FRPFrameCodec.decodeHeader(frameData.prefix(9))
        XCTAssertEqual(header.type, .login)
        XCTAssertEqual(Int(header.length), frameData.count - 9)

        // 3. Decode payload
        let decoded = try FRPFrameCodec.decodePayload(type: header.type, payload: frameData.suffix(from: 9))
        guard let decodedLogin = decoded as? FRPLoginMessage else {
            XCTFail("Decoded message is not FRPLoginMessage")
            return
        }

        XCTAssertEqual(decodedLogin.version, "0.61.0")
        XCTAssertEqual(decodedLogin.hostname, "my-mac")
        XCTAssertEqual(decodedLogin.os, "darwin")
        XCTAssertEqual(decodedLogin.arch, "arm64")
        XCTAssertEqual(decodedLogin.user, "alice")
        XCTAssertEqual(decodedLogin.privilegeKey, "abcd1234ef567890")
        XCTAssertEqual(decodedLogin.timestamp, 123456789)
        XCTAssertEqual(decodedLogin.runID, "run-001")
        XCTAssertEqual(decodedLogin.metas?["client_version"], "1.0.0")
        XCTAssertEqual(decodedLogin.clientSpec?.type, "test")
        XCTAssertEqual(decodedLogin.poolCount, 5)
    }

    func testEncodeAndDecodeLoginRespMessage() throws {
        let resp = FRPLoginRespMessage(version: "0.61.0", runID: "run-xyz-789", error: nil)
        let frameData = try FRPFrameCodec.encode(resp)
        let header = try FRPFrameCodec.decodeHeader(frameData.prefix(9))
        XCTAssertEqual(header.type, .loginResp)

        let decoded = try FRPFrameCodec.decodePayload(type: header.type, payload: frameData.suffix(from: 9))
        guard let decodedResp = decoded as? FRPLoginRespMessage else {
            XCTFail("Expected FRPLoginRespMessage")
            return
        }
        XCTAssertEqual(decodedResp.version, "0.61.0")
        XCTAssertEqual(decodedResp.runID, "run-xyz-789")
        XCTAssertNil(decodedResp.error)

        // Error response
        let errResp = FRPLoginRespMessage(version: "0.61.0", runID: nil, error: "Token mismatch")
        let errData = try FRPFrameCodec.encode(errResp)
        let decodedErr = try FRPFrameCodec.decodePayload(type: .loginResp, payload: errData.suffix(from: 9)) as? FRPLoginRespMessage
        XCTAssertEqual(decodedErr?.error, "Token mismatch")
    }

    func testEncodeAndDecodeNewProxyMessage() throws {
        var proxy = FRPNewProxyMessage(
            proxyName: "web_proxy",
            proxyType: "http",
            useEncryption: true,
            useCompression: true,
            remotePort: 8080,
            customDomains: ["example.com"],
            subdomain: "blog",
            locations: ["/api"],
            sk: "secret_k",
            multiplexer: "httpconnect"
        )
        proxy.httpUser = "user1"
        proxy.httpPwd = "pwd1"
        proxy.hostHeaderRewrite = "origin.local"

        let frameData = try FRPFrameCodec.encode(proxy)
        XCTAssertEqual(frameData[0], FRPMessageType.newProxy.rawValue)

        let header = try FRPFrameCodec.decodeHeader(frameData.prefix(9))
        XCTAssertEqual(header.type, .newProxy)

        let decoded = try FRPFrameCodec.decodePayload(type: header.type, payload: frameData.suffix(from: 9))
        guard let decodedProxy = decoded as? FRPNewProxyMessage else {
            XCTFail("Decoded message is not FRPNewProxyMessage")
            return
        }

        XCTAssertEqual(decodedProxy.proxyName, "web_proxy")
        XCTAssertEqual(decodedProxy.proxyType, "http")
        XCTAssertEqual(decodedProxy.useEncryption, true)
        XCTAssertEqual(decodedProxy.useCompression, true)
        XCTAssertEqual(decodedProxy.remotePort, 8080)
        XCTAssertEqual(decodedProxy.customDomains, ["example.com"])
        XCTAssertEqual(decodedProxy.subdomain, "blog")
        XCTAssertEqual(decodedProxy.locations, ["/api"])
        XCTAssertEqual(decodedProxy.httpUser, "user1")
        XCTAssertEqual(decodedProxy.httpPwd, "pwd1")
        XCTAssertEqual(decodedProxy.hostHeaderRewrite, "origin.local")
        XCTAssertEqual(decodedProxy.sk, "secret_k")
        XCTAssertEqual(decodedProxy.multiplexer, "httpconnect")
    }

    func testEncodeAndDecodeNewProxyResp() throws {
        let resp = FRPNewProxyRespMessage(proxyName: "tcp_test", remoteAddr: "1.2.3.4:9000", error: nil)
        let data = try FRPFrameCodec.encode(resp)
        let header = try FRPFrameCodec.decodeHeader(data.prefix(9))
        XCTAssertEqual(header.type, .newProxyResp)

        let decoded = try FRPFrameCodec.decodePayload(type: header.type, payload: data.suffix(from: 9)) as? FRPNewProxyRespMessage
        XCTAssertEqual(decoded?.proxyName, "tcp_test")
        XCTAssertEqual(decoded?.remoteAddr, "1.2.3.4:9000")
        XCTAssertNil(decoded?.error)
    }

    func testPingPongMessages() throws {
        let ping = FRPPingMessage(privilegeKey: "pingkey", timestamp: 99999)
        let pingData = try FRPFrameCodec.encode(ping)
        XCTAssertEqual(pingData[0], FRPMessageType.ping.rawValue)
        let decodedPing = try FRPFrameCodec.decodePayload(type: .ping, payload: pingData.suffix(from: 9)) as? FRPPingMessage
        XCTAssertEqual(decodedPing?.privilegeKey, "pingkey")
        XCTAssertEqual(decodedPing?.timestamp, 99999)

        let pong = FRPPongMessage(error: "err")
        let pongData = try FRPFrameCodec.encode(pong)
        XCTAssertEqual(pongData[0], FRPMessageType.pong.rawValue)
        let decodedPong = try FRPFrameCodec.decodePayload(type: .pong, payload: pongData.suffix(from: 9)) as? FRPPongMessage
        XCTAssertEqual(decodedPong?.error, "err")
    }

    func testWorkConnMessages() throws {
        // 1. ReqWorkConn
        let reqWork = FRPReqWorkConnMessage()
        let reqData = try FRPFrameCodec.encode(reqWork)
        let reqHeader = try FRPFrameCodec.decodeHeader(reqData.prefix(9))
        XCTAssertEqual(reqHeader.type, .reqWorkConn)
        let decodedReq = try FRPFrameCodec.decodePayload(type: .reqWorkConn, payload: reqData.suffix(from: 9))
        XCTAssertTrue(decodedReq is FRPReqWorkConnMessage)

        // 2. NewWorkConn
        let newWork = FRPNewWorkConnMessage(runID: "test-run-123", privilegeKey: "pk-abc", timestamp: 55555)
        let newData = try FRPFrameCodec.encode(newWork)
        let newHeader = try FRPFrameCodec.decodeHeader(newData.prefix(9))
        XCTAssertEqual(newHeader.type, .newWorkConn)
        let decodedNew = try FRPFrameCodec.decodePayload(type: .newWorkConn, payload: newData.suffix(from: 9)) as? FRPNewWorkConnMessage
        XCTAssertEqual(decodedNew?.runID, "test-run-123")
        XCTAssertEqual(decodedNew?.privilegeKey, "pk-abc")
        XCTAssertEqual(decodedNew?.timestamp, 55555)

        // 3. StartWorkConn
        let startWork = FRPStartWorkConnMessage(
            proxyName: "my_proxy",
            srcAddr: "10.0.0.1",
            dstAddr: "127.0.0.1",
            srcPort: 54321,
            dstPort: 8080,
            error: nil
        )
        let startData = try FRPFrameCodec.encode(startWork)
        let startHeader = try FRPFrameCodec.decodeHeader(startData.prefix(9))
        XCTAssertEqual(startHeader.type, .startWorkConn)
        let decodedStart = try FRPFrameCodec.decodePayload(type: .startWorkConn, payload: startData.suffix(from: 9)) as? FRPStartWorkConnMessage
        XCTAssertEqual(decodedStart?.proxyName, "my_proxy")
        XCTAssertEqual(decodedStart?.srcAddr, "10.0.0.1")
        XCTAssertEqual(decodedStart?.srcPort, 54321)

        // 4. CloseProxy
        let closeProxy = FRPCloseProxyMessage(proxyName: "my_proxy")
        let closeData = try FRPFrameCodec.encode(closeProxy)
        let closeHeader = try FRPFrameCodec.decodeHeader(closeData.prefix(9))
        XCTAssertEqual(closeHeader.type, .closeProxy)
        let decodedClose = try FRPFrameCodec.decodePayload(type: .closeProxy, payload: closeData.suffix(from: 9)) as? FRPCloseProxyMessage
        XCTAssertEqual(decodedClose?.proxyName, "my_proxy")
    }

    func testInvalidHeaderDecoding() {
        // Less than 9 bytes
        XCTAssertThrowsError(try FRPFrameCodec.decodeHeader(Data([0x6f, 0x00]))) { error in
            guard case FRPFrameError.unexpectedEOF = error else {
                XCTFail("Expected unexpectedEOF error")
                return
            }
        }

        // Unknown type byte
        var invalidData = Data(repeating: 0, count: 9)
        invalidData[0] = 0xFF // Unknown type
        XCTAssertThrowsError(try FRPFrameCodec.decodeHeader(invalidData)) { error in
            guard case FRPFrameError.unsupportedMessageType(let byte) = error else {
                XCTFail("Expected unsupportedMessageType")
                return
            }
            XCTAssertEqual(byte, 0xFF)
        }

        // Negative length (via crafted big-endian bytes with MSB set)
        var negativeLenData = Data([FRPMessageType.login.rawValue])
        var negativeLen = Int64(-5).bigEndian
        withUnsafeBytes(of: &negativeLen) { negativeLenData.append(contentsOf: $0) }
        XCTAssertThrowsError(try FRPFrameCodec.decodeHeader(negativeLenData)) { error in
            guard case FRPFrameError.invalidLength = error else {
                XCTFail("Expected invalidLength error")
                return
            }
        }

        // Exceedingly large length (> 10MB)
        var largeLenData = Data([FRPMessageType.login.rawValue])
        var largeLen = Int64(20 * 1024 * 1024).bigEndian
        withUnsafeBytes(of: &largeLen) { largeLenData.append(contentsOf: $0) }
        XCTAssertThrowsError(try FRPFrameCodec.decodeHeader(largeLenData)) { error in
            guard case FRPFrameError.invalidLength = error else {
                XCTFail("Expected invalidLength error")
                return
            }
        }
    }

    func testMalformedJSONPayloadDecoding() {
        let garbage = Data("this is not json".utf8)
        XCTAssertThrowsError(try FRPFrameCodec.decodePayload(type: .login, payload: garbage)) { error in
            guard case FRPFrameError.decodingError = error else {
                XCTFail("Expected decodingError")
                return
            }
        }
    }
}
