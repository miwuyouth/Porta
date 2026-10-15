import Foundation

public enum YamuxType: UInt8, Sendable {
    case data = 0
    case windowUpdate = 1
    case ping = 2
    case goAway = 3
}

public struct YamuxFlags: OptionSet, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let syn = YamuxFlags(rawValue: 1)
    public static let ack = YamuxFlags(rawValue: 2)
    public static let fin = YamuxFlags(rawValue: 4)
    public static let rst = YamuxFlags(rawValue: 8)
}

public struct YamuxHeader: Sendable {
    public static let headerSize = 12

    public var version: UInt8
    public var type: YamuxType
    public var flags: YamuxFlags
    public var streamID: UInt32
    public var length: UInt32

    public init(
        version: UInt8 = 0,
        type: YamuxType,
        flags: YamuxFlags = [],
        streamID: UInt32,
        length: UInt32
    ) {
        self.version = version
        self.type = type
        self.flags = flags
        self.streamID = streamID
        self.length = length
    }

    public func encode() -> Data {
        var data = Data(capacity: YamuxHeader.headerSize)
        data.append(version)
        data.append(type.rawValue)

        var bigFlags = flags.rawValue.bigEndian
        withUnsafeBytes(of: &bigFlags) { data.append(contentsOf: $0) }

        var bigStreamID = streamID.bigEndian
        withUnsafeBytes(of: &bigStreamID) { data.append(contentsOf: $0) }

        var bigLength = length.bigEndian
        withUnsafeBytes(of: &bigLength) { data.append(contentsOf: $0) }

        return data
    }

    public static func decode(from data: Data) -> YamuxHeader? {
        guard data.count >= headerSize else { return nil }

        let start = data.startIndex
        let version = data[start]
        guard let type = YamuxType(rawValue: data[start + 1]) else { return nil }

        let flagsRaw = data.subdata(in: (start + 2)..<(start + 4)).withUnsafeBytes { $0.load(as: UInt16.self) }
        let streamIDRaw = data.subdata(in: (start + 4)..<(start + 8)).withUnsafeBytes { $0.load(as: UInt32.self) }
        let lengthRaw = data.subdata(in: (start + 8)..<(start + 12)).withUnsafeBytes { $0.load(as: UInt32.self) }

        return YamuxHeader(
            version: version,
            type: type,
            flags: YamuxFlags(rawValue: UInt16(bigEndian: flagsRaw)),
            streamID: UInt32(bigEndian: streamIDRaw),
            length: UInt32(bigEndian: lengthRaw)
        )
    }
}
