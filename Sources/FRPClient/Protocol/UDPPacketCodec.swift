import Foundation

public struct UDPPacket: Equatable, Sendable {
    public var proxyName: String
    public var seq: UInt64
    public var payload: Data

    public init(proxyName: String, seq: UInt64, payload: Data) {
        self.proxyName = proxyName
        self.seq = seq
        self.payload = payload
    }
}

public enum UDPPacketCodecError: Error, Equatable {
    case headerTooShort
    case invalidLength
    case payloadTooLarge
    case corruptHeader
}

public enum UDPPacketCodec {
    public static let maxUDPPacketSize: Int = 64 * 1024

    /// Wire format:
    /// [2 bytes big-endian proxyName length] + [proxyName UTF-8] + [8 bytes big-endian seq] + [N bytes payload]
    public static func encode(_ packet: UDPPacket) throws -> Data {
        let nameData = Data(packet.proxyName.utf8)
        guard nameData.count <= 65535 else { throw UDPPacketCodecError.invalidLength }
        guard packet.payload.count <= maxUDPPacketSize else { throw UDPPacketCodecError.payloadTooLarge }

        var data = Data(capacity: 2 + nameData.count + 8 + packet.payload.count)

        var nameLen = UInt16(nameData.count).bigEndian
        withUnsafeBytes(of: &nameLen) { data.append(contentsOf: $0) }
        data.append(nameData)

        var seqBE = packet.seq.bigEndian
        withUnsafeBytes(of: &seqBE) { data.append(contentsOf: $0) }

        data.append(packet.payload)
        return data
    }

    public static func decode(_ data: Data) throws -> UDPPacket {
        guard data.count >= 10 else { throw UDPPacketCodecError.headerTooShort }

        let nameLen = data.prefix(2).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self).bigEndian }
        let headerSize = 2 + Int(nameLen) + 8
        guard data.count >= headerSize else { throw UDPPacketCodecError.corruptHeader }

        let nameStart = data.index(data.startIndex, offsetBy: 2)
        let nameEnd = data.index(nameStart, offsetBy: Int(nameLen))
        guard let proxyName = String(data: data[nameStart..<nameEnd], encoding: .utf8) else {
            throw UDPPacketCodecError.corruptHeader
        }

        let seqStart = nameEnd
        let seqEnd = data.index(seqStart, offsetBy: 8)
        let seq = data[seqStart..<seqEnd].withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).bigEndian }

        let payload = Data(data[seqEnd...])
        return UDPPacket(proxyName: proxyName, seq: seq, payload: payload)
    }

    /// Slices a large payload into chunks of maxChunkSize.
    public static func slicePayload(_ payload: Data, maxChunkSize: Int) -> [Data] {
        guard maxChunkSize > 0 else { return [payload] }
        var chunks: [Data] = []
        var offset = 0
        while offset < payload.count {
            let len = min(maxChunkSize, payload.count - offset)
            chunks.append(payload.subdata(in: offset..<(offset + len)))
            offset += len
        }
        return chunks
    }

    /// Reassembles chunks into a single Data payload.
    public static func reassembleChunks(_ chunks: [Data]) -> Data {
        var total = Data()
        for chunk in chunks {
            total.append(chunk)
        }
        return total
    }
}

public final class BufferPool: @unchecked Sendable {
    private let lock = SafeLock()
    private var pool: [Data] = []
    private let bufferCapacity: Int

    public init(capacity: Int = 4096) {
        self.bufferCapacity = capacity
    }

    public func acquire() -> Data {
        lock.withLock {
            if !pool.isEmpty {
                var buf = pool.removeLast()
                buf.removeAll(keepingCapacity: true)
                return buf
            }
            return Data(capacity: bufferCapacity)
        }
    }

    public func release(_ buffer: Data) {
        lock.withLock {
            if pool.count < 32 {
                pool.append(buffer)
            }
        }
    }

    public var availableCount: Int {
        lock.withLock { pool.count }
    }
}
