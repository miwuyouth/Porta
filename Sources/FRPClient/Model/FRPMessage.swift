import Foundation

public enum FRPMessageType: UInt8, Sendable {
    case login = 0x6f              // 'o'
    case loginResp = 0x31          // '1'
    case newProxy = 0x70           // 'p'
    case newProxyResp = 0x32       // '2'
    case closeProxy = 0x63         // 'c'
    case newWorkConn = 0x77        // 'w'
    case reqWorkConn = 0x72        // 'r'
    case startWorkConn = 0x73      // 's'
    case ping = 0x68               // 'h'
    case pong = 0x34               // '4'
    case natHoleSid = 0x69         // 'i'
    case natHoleClient = 0x6b      // 'k'
    case natHoleResp = 0x6d        // 'm'
    case natHoleReport = 0x6e      // 'n'
    case udpPacket = 0x75          // 'u'
}

public protocol FRPMessage: Codable, Sendable {
    static var messageType: FRPMessageType { get }
}

public struct FRPClientSpec: Codable, Sendable {
    public var type: String?
    public var alwaysAuthPass: Bool?

    enum CodingKeys: String, CodingKey {
        case type
        case alwaysAuthPass = "always_auth_pass"
    }

    public init(type: String? = nil, alwaysAuthPass: Bool? = nil) {
        self.type = type
        self.alwaysAuthPass = alwaysAuthPass
    }
}

public struct FRPLoginMessage: FRPMessage {
    public static let messageType: FRPMessageType = .login

    public var version: String
    public var hostname: String
    public var os: String
    public var arch: String
    public var user: String
    public var privilegeKey: String
    public var timestamp: Int64
    public var runID: String
    public var metas: [String: String]?
    public var clientSpec: FRPClientSpec?
    public var poolCount: Int

    enum CodingKeys: String, CodingKey {
        case version
        case hostname
        case os
        case arch
        case user
        case privilegeKey = "privilege_key"
        case timestamp
        case runID = "run_id"
        case metas
        case clientSpec = "client_spec"
        case poolCount = "pool_count"
    }

    public init(
        version: String = "0.61.0",
        hostname: String = "",
        os: String = "darwin",
        arch: String = "arm64",
        user: String = "",
        privilegeKey: String = "",
        timestamp: Int64 = 0,
        runID: String = "",
        metas: [String: String]? = nil,
        clientSpec: FRPClientSpec? = nil,
        poolCount: Int = 1
    ) {
        self.version = version
        self.hostname = hostname
        self.os = os
        self.arch = arch
        self.user = user
        self.privilegeKey = privilegeKey
        self.timestamp = timestamp
        self.runID = runID
        self.metas = metas
        self.clientSpec = clientSpec
        self.poolCount = poolCount
    }
}

public struct FRPLoginRespMessage: FRPMessage {
    public static let messageType: FRPMessageType = .loginResp

    public var version: String?
    public var runID: String?
    public var error: String?

    enum CodingKeys: String, CodingKey {
        case version
        case runID = "run_id"
        case error
    }

    public init(version: String? = nil, runID: String? = nil, error: String? = nil) {
        self.version = version
        self.runID = runID
        self.error = error
    }
}

public struct FRPNewProxyMessage: FRPMessage {
    public static let messageType: FRPMessageType = .newProxy

    public var proxyName: String
    public var proxyType: String
    public var useEncryption: Bool?
    public var useCompression: Bool?
    public var bandwidthLimit: String?
    public var bandwidthLimitMode: String?
    public var group: String?
    public var groupKey: String?
    public var metas: [String: String]?
    public var annotations: [String: String]?

    // tcp and udp only
    public var remotePort: Int?

    // http and https only
    public var customDomains: [String]?
    public var subdomain: String?
    public var locations: [String]?
    public var httpUser: String?
    public var httpPwd: String?
    public var hostHeaderRewrite: String?
    public var headers: [String: String]?
    public var responseHeaders: [String: String]?
    public var routeByHTTPUser: String?

    // stcp, sudp, xtcp
    public var sk: String?
    public var allowUsers: [String]?

    // tcpmux
    public var multiplexer: String?

    enum CodingKeys: String, CodingKey {
        case proxyName = "proxy_name"
        case proxyType = "proxy_type"
        case useEncryption = "use_encryption"
        case useCompression = "use_compression"
        case bandwidthLimit = "bandwidth_limit"
        case bandwidthLimitMode = "bandwidth_limit_mode"
        case group
        case groupKey = "group_key"
        case metas
        case annotations
        case remotePort = "remote_port"
        case customDomains = "custom_domains"
        case subdomain
        case locations
        case httpUser = "http_user"
        case httpPwd = "http_pwd"
        case hostHeaderRewrite = "host_header_rewrite"
        case headers
        case responseHeaders = "response_headers"
        case routeByHTTPUser = "route_by_http_user"
        case sk
        case allowUsers = "allow_users"
        case multiplexer
    }

    public init(
        proxyName: String,
        proxyType: String,
        useEncryption: Bool? = nil,
        useCompression: Bool? = nil,
        remotePort: Int? = nil,
        customDomains: [String]? = nil,
        subdomain: String? = nil,
        locations: [String]? = nil,
        sk: String? = nil,
        multiplexer: String? = nil
    ) {
        self.proxyName = proxyName
        self.proxyType = proxyType
        self.useEncryption = useEncryption
        self.useCompression = useCompression
        self.remotePort = remotePort
        self.customDomains = customDomains
        self.subdomain = subdomain
        self.locations = locations
        self.sk = sk
        self.multiplexer = multiplexer
    }
}

public struct FRPNewProxyRespMessage: FRPMessage {
    public static let messageType: FRPMessageType = .newProxyResp

    public var proxyName: String?
    public var remoteAddr: String?
    public var error: String?

    enum CodingKeys: String, CodingKey {
        case proxyName = "proxy_name"
        case remoteAddr = "remote_addr"
        case error
    }

    public init(proxyName: String? = nil, remoteAddr: String? = nil, error: String? = nil) {
        self.proxyName = proxyName
        self.remoteAddr = remoteAddr
        self.error = error
    }
}

public struct FRPCloseProxyMessage: FRPMessage {
    public static let messageType: FRPMessageType = .closeProxy

    public var proxyName: String

    enum CodingKeys: String, CodingKey {
        case proxyName = "proxy_name"
    }

    public init(proxyName: String) {
        self.proxyName = proxyName
    }
}

public struct FRPReqWorkConnMessage: FRPMessage {
    public static let messageType: FRPMessageType = .reqWorkConn
    public init() {}
}

public struct FRPNewWorkConnMessage: FRPMessage {
    public static let messageType: FRPMessageType = .newWorkConn

    public var runID: String
    public var privilegeKey: String?
    public var timestamp: Int64?

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case privilegeKey = "privilege_key"
        case timestamp
    }

    public init(runID: String, privilegeKey: String? = nil, timestamp: Int64? = nil) {
        self.runID = runID
        self.privilegeKey = privilegeKey
        self.timestamp = timestamp
    }
}

public struct FRPStartWorkConnMessage: FRPMessage {
    public static let messageType: FRPMessageType = .startWorkConn

    public var proxyName: String
    public var srcAddr: String?
    public var dstAddr: String?
    public var srcPort: UInt16?
    public var dstPort: UInt16?
    public var error: String?

    enum CodingKeys: String, CodingKey {
        case proxyName = "proxy_name"
        case srcAddr = "src_addr"
        case dstAddr = "dst_addr"
        case srcPort = "src_port"
        case dstPort = "dst_port"
        case error
    }

    public init(
        proxyName: String,
        srcAddr: String? = nil,
        dstAddr: String? = nil,
        srcPort: UInt16? = nil,
        dstPort: UInt16? = nil,
        error: String? = nil
    ) {
        self.proxyName = proxyName
        self.srcAddr = srcAddr
        self.dstAddr = dstAddr
        self.srcPort = srcPort
        self.dstPort = dstPort
        self.error = error
    }
}

public struct FRPPingMessage: FRPMessage {
    public static let messageType: FRPMessageType = .ping

    public var privilegeKey: String?
    public var timestamp: Int64?

    enum CodingKeys: String, CodingKey {
        case privilegeKey = "privilege_key"
        case timestamp
    }

    public init(privilegeKey: String? = nil, timestamp: Int64? = nil) {
        self.privilegeKey = privilegeKey
        self.timestamp = timestamp
    }
}

public struct FRPPongMessage: FRPMessage {
    public static let messageType: FRPMessageType = .pong

    public var error: String?

    enum CodingKeys: String, CodingKey {
        case error
    }

    public init(error: String? = nil) {
        self.error = error
    }
}

public struct FRPNatHoleSidMessage: FRPMessage {
    public static let messageType: FRPMessageType = .natHoleSid

    public var sid: String

    enum CodingKeys: String, CodingKey {
        case sid
    }

    public init(sid: String = "") {
        self.sid = sid
    }
}

public struct FRPNatHoleClientMessage: FRPMessage {
    public static let messageType: FRPMessageType = .natHoleClient

    public var sid: String
    public var proxyName: String

    enum CodingKeys: String, CodingKey {
        case sid
        case proxyName = "proxy_name"
    }

    public init(sid: String = "", proxyName: String = "") {
        self.sid = sid
        self.proxyName = proxyName
    }
}

public struct FRPNatHoleRespMessage: FRPMessage {
    public static let messageType: FRPMessageType = .natHoleResp

    public var sid: String
    public var visitorCandidateAddress: [String]?
    public var clientCandidateAddress: [String]?
    public var error: String?

    enum CodingKeys: String, CodingKey {
        case sid
        case visitorCandidateAddress = "visitor_candidate_address"
        case clientCandidateAddress = "client_candidate_address"
        case error
    }

    public init(
        sid: String = "",
        visitorCandidateAddress: [String]? = nil,
        clientCandidateAddress: [String]? = nil,
        error: String? = nil
    ) {
        self.sid = sid
        self.visitorCandidateAddress = visitorCandidateAddress
        self.clientCandidateAddress = clientCandidateAddress
        self.error = error
    }
}

public struct FRPNatHoleReportMessage: FRPMessage {
    public static let messageType: FRPMessageType = .natHoleReport

    public var sid: String
    public var candidateAddress: [String]

    enum CodingKeys: String, CodingKey {
        case sid
        case candidateAddress = "candidate_address"
    }

    public init(sid: String = "", candidateAddress: [String] = []) {
        self.sid = sid
        self.candidateAddress = candidateAddress
    }
}

public struct FRPUDPPacketMessage: FRPMessage {
    public static let messageType: FRPMessageType = .udpPacket

    public var proxyName: String
    public var content: String
    public var seq: UInt64?

    enum CodingKeys: String, CodingKey {
        case proxyName = "proxy_name"
        case content
        case seq
    }

    public init(proxyName: String = "", content: String = "", seq: UInt64? = nil) {
        self.proxyName = proxyName
        self.content = content
        self.seq = seq
    }
}

