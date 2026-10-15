import Foundation

public enum AsyncConnectionError: Error, CustomStringConvertible, LocalizedError, Sendable {
    case closed
    case connectionFailed(String)
    case readFailed(String)
    case writeFailed(String)
    case timeout

    public var description: String {
        switch self {
        case .closed:
            return "连接已关闭 (Connection closed)"
        case .connectionFailed(let reason):
            return "连接失败: \(reason)"
        case .readFailed(let reason):
            return "读取数据失败: \(reason)"
        case .writeFailed(let reason):
            return "写入数据失败: \(reason)"
        case .timeout:
            return "连接服务器超时 (Connection timed out)"
        }
    }

    public var errorDescription: String? {
        description
    }
}

public protocol AsyncConnection: Sendable, AnyObject {
    /// Reads at most `maxCount` bytes. Returns empty Data if EOF reached.
    func read(upToCount maxCount: Int) async throws -> Data

    /// Reads exactly `count` bytes. Throws if EOF reached before satisfying count.
    func read(exactCount count: Int) async throws -> Data

    /// Writes all bytes in data.
    func write(_ data: Data) async throws

    /// Closes the connection.
    func close()

    /// Checks if connection is marked closed.
    var isClosed: Bool { get }
}

public extension AsyncConnection {
    /// Helper to read an entire FRP framed message.
    func readMessage() async throws -> any FRPMessage {
        // 1. Read 9-byte header
        let headerData = try await read(exactCount: 9)
        let (msgType, payloadLength) = try FRPFrameCodec.decodeHeader(headerData)

        // 2. Read JSON payload
        let payloadData: Data
        if payloadLength > 0 {
            payloadData = try await read(exactCount: Int(payloadLength))
        } else {
            payloadData = Data()
        }

        // 3. Decode message
        return try FRPFrameCodec.decodePayload(type: msgType, payload: payloadData)
    }

    /// Helper to write an FRP framed message.
    func writeMessage<M: FRPMessage>(_ message: M) async throws {
        let frameData = try FRPFrameCodec.encode(message)
        try await write(frameData)
    }
}
