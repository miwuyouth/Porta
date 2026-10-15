import Foundation

public enum FRPFrameError: Error, CustomStringConvertible, LocalizedError, Sendable {
    case invalidLength(Int64)
    case unsupportedMessageType(UInt8)
    case unexpectedEOF
    case decodingError(String)
    case encodingError(String)

    public var description: String {
        switch self {
        case .invalidLength(let len):
            return "Invalid FRP message payload length: \(len)"
        case .unsupportedMessageType(let byte):
            let charStr = UnicodeScalar(UInt32(byte)).map { String($0) } ?? "?"
            return "Unsupported FRP message type byte: 0x\(String(format: "%02x", byte)) ('\(charStr)')"
        case .unexpectedEOF:
            return "Unexpected EOF while reading FRP message"
        case .decodingError(let msg):
            return "FRP message decoding error: \(msg)"
        case .encodingError(let msg):
            return "FRP message encoding error: \(msg)"
        }
    }

    public var errorDescription: String? {
        description
    }
}

public enum FRPFrameCodec {
    private static let maxPayloadLength: Int64 = 10 * 1024 * 1024 // 10MB limit

    /// Encodes a FRPMessage into wire frame bytes:
    /// [1 byte type] + [8 bytes Big-Endian Int64 length] + [N bytes JSON UTF-8 payload]
    public static func encode<M: FRPMessage>(_ message: M) throws -> Data {
        let encoder = JSONEncoder()
        let payload: Data
        do {
            payload = try encoder.encode(message)
        } catch {
            throw FRPFrameError.encodingError(error.localizedDescription)
        }

        var frameData = Data(capacity: 1 + 8 + payload.count)
        frameData.append(M.messageType.rawValue)

        var bigEndianLength = Int64(payload.count).bigEndian
        withUnsafeBytes(of: &bigEndianLength) { rawBuffer in
            frameData.append(contentsOf: rawBuffer)
        }

        frameData.append(payload)
        return frameData
    }

    /// Decodes a frame header from 9-byte raw buffer.
    public static func decodeHeader(_ headerData: Data) throws -> (type: FRPMessageType, length: Int64) {
        guard headerData.count == 9 else {
            throw FRPFrameError.unexpectedEOF
        }

        let typeRaw = headerData[headerData.startIndex]
        guard let msgType = FRPMessageType(rawValue: typeRaw) else {
            throw FRPFrameError.unsupportedMessageType(typeRaw)
        }

        let lengthData = headerData.subdata(in: (headerData.startIndex + 1)..<(headerData.startIndex + 9))
        let rawBigEndianLength = lengthData.withUnsafeBytes { $0.load(as: Int64.self) }
        let length = Int64(bigEndian: rawBigEndianLength)

        guard length >= 0 && length <= maxPayloadLength else {
            throw FRPFrameError.invalidLength(length)
        }

        return (msgType, length)
    }

    /// Parses JSON payload data into the corresponding message based on type.
    public static func decodePayload(type: FRPMessageType, payload: Data) throws -> any FRPMessage {
        let decoder = JSONDecoder()
        do {
            switch type {
            case .login:
                return try decoder.decode(FRPLoginMessage.self, from: payload)
            case .loginResp:
                return try decoder.decode(FRPLoginRespMessage.self, from: payload)
            case .newProxy:
                return try decoder.decode(FRPNewProxyMessage.self, from: payload)
            case .newProxyResp:
                return try decoder.decode(FRPNewProxyRespMessage.self, from: payload)
            case .closeProxy:
                return try decoder.decode(FRPCloseProxyMessage.self, from: payload)
            case .newWorkConn:
                return try decoder.decode(FRPNewWorkConnMessage.self, from: payload)
            case .reqWorkConn:
                return try decoder.decode(FRPReqWorkConnMessage.self, from: payload)
            case .startWorkConn:
                return try decoder.decode(FRPStartWorkConnMessage.self, from: payload)
            case .ping:
                return try decoder.decode(FRPPingMessage.self, from: payload)
            case .pong:
                return try decoder.decode(FRPPongMessage.self, from: payload)
            case .natHoleSid:
                return try decoder.decode(FRPNatHoleSidMessage.self, from: payload)
            case .natHoleClient:
                return try decoder.decode(FRPNatHoleClientMessage.self, from: payload)
            case .natHoleResp:
                return try decoder.decode(FRPNatHoleRespMessage.self, from: payload)
            case .natHoleReport:
                return try decoder.decode(FRPNatHoleReportMessage.self, from: payload)
            case .udpPacket:
                return try decoder.decode(FRPUDPPacketMessage.self, from: payload)
            }
        } catch {
            throw FRPFrameError.decodingError("Failed to decode \(type) from payload: \(error.localizedDescription)")
        }
    }
}
