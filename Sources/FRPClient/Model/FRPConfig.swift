import Foundation

public struct FRPAuthConfig: Sendable, Codable {
    public var method: String
    public var token: String
    public var additionalScopes: [String]?

    public init(method: String = "token", token: String = "", additionalScopes: [String]? = nil) {
        self.method = method
        self.token = token
        self.additionalScopes = additionalScopes
    }
}

public struct FRPTransportConfig: Sendable, Codable {
    public var protocolType: String
    public var tcpMux: Bool
    public var tlsEnable: Bool
    public var tlsServerName: String?
    public var heartbeatInterval: TimeInterval
    public var heartbeatTimeout: TimeInterval
    public var dialServerTimeout: TimeInterval
    public var poolCount: Int

    enum CodingKeys: String, CodingKey {
        case protocolType
        case tcpMux
        case tlsEnable
        case tlsServerName
        case heartbeatInterval
        case heartbeatTimeout
        case dialServerTimeout
        case poolCount
    }

    public init(
        protocolType: String = "tcp",
        tcpMux: Bool = true,
        tlsEnable: Bool = false,
        tlsServerName: String? = nil,
        heartbeatInterval: TimeInterval = 30,
        heartbeatTimeout: TimeInterval = 90,
        dialServerTimeout: TimeInterval = 10,
        poolCount: Int = 0
    ) {
        self.protocolType = protocolType
        self.tcpMux = tcpMux
        self.tlsEnable = tlsEnable
        self.tlsServerName = tlsServerName
        self.heartbeatInterval = heartbeatInterval
        self.heartbeatTimeout = heartbeatTimeout
        self.dialServerTimeout = dialServerTimeout
        self.poolCount = poolCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.protocolType = try container.decodeIfPresent(String.self, forKey: .protocolType) ?? "tcp"
        self.tcpMux = try container.decodeIfPresent(Bool.self, forKey: .tcpMux) ?? true
        self.tlsEnable = try container.decodeIfPresent(Bool.self, forKey: .tlsEnable) ?? false
        self.tlsServerName = try container.decodeIfPresent(String.self, forKey: .tlsServerName)
        self.heartbeatInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .heartbeatInterval) ?? 30
        self.heartbeatTimeout = try container.decodeIfPresent(TimeInterval.self, forKey: .heartbeatTimeout) ?? 90
        self.dialServerTimeout = try container.decodeIfPresent(TimeInterval.self, forKey: .dialServerTimeout) ?? 10
        self.poolCount = try container.decodeIfPresent(Int.self, forKey: .poolCount) ?? 0
    }
}

public enum FRPProxyType: String, Sendable, Codable {
    case tcp
    case udp
    case http
    case https
    case stcp
    case sudp
    case tcpmux
    case xtcp
}

public struct FRPProxyConfig: Sendable, Codable, Identifiable {
    public var id: String { name }

    public var name: String
    public var type: FRPProxyType
    public var localIP: String
    public var localPort: Int

    public var useEncryption: Bool
    public var useCompression: Bool

    // TCP / UDP
    public var remotePort: Int?

    // HTTP / HTTPS
    public var customDomains: [String]?
    public var subdomain: String?
    public var locations: [String]?
    public var hostHeaderRewrite: String?
    public var httpUser: String?
    public var httpPassword: String?

    // STCP
    public var secretKey: String?
    public var multiplexer: String?

    public init(
        name: String,
        type: FRPProxyType = .tcp,
        localIP: String = "127.0.0.1",
        localPort: Int,
        remotePort: Int? = nil,
        customDomains: [String]? = nil,
        subdomain: String? = nil,
        locations: [String]? = nil,
        hostHeaderRewrite: String? = nil,
        httpUser: String? = nil,
        httpPassword: String? = nil,
        secretKey: String? = nil,
        multiplexer: String? = nil,
        useEncryption: Bool = false,
        useCompression: Bool = false
    ) {
        self.name = name
        self.type = type
        self.localIP = localIP
        self.localPort = localPort
        self.remotePort = remotePort
        self.customDomains = customDomains
        self.subdomain = subdomain
        self.locations = locations
        self.hostHeaderRewrite = hostHeaderRewrite
        self.httpUser = httpUser
        self.httpPassword = httpPassword
        self.secretKey = secretKey
        self.multiplexer = multiplexer
        self.useEncryption = useEncryption
        self.useCompression = useCompression
    }

    enum CodingKeys: String, CodingKey {
        case name, type, localIP, localPort, useEncryption, useCompression
        case remotePort, customDomains, subdomain, locations, hostHeaderRewrite
        case httpUser, httpPassword, secretKey, multiplexer
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.type = (try? container.decodeIfPresent(FRPProxyType.self, forKey: .type)) ?? .tcp
        self.localIP = (try? container.decodeIfPresent(String.self, forKey: .localIP)) ?? "127.0.0.1"
        self.localPort = try container.decode(Int.self, forKey: .localPort)
        self.remotePort = try? container.decodeIfPresent(Int.self, forKey: .remotePort)
        self.customDomains = try? container.decodeIfPresent([String].self, forKey: .customDomains)
        self.subdomain = try? container.decodeIfPresent(String.self, forKey: .subdomain)
        self.locations = try? container.decodeIfPresent([String].self, forKey: .locations)
        self.hostHeaderRewrite = try? container.decodeIfPresent(String.self, forKey: .hostHeaderRewrite)
        self.httpUser = try? container.decodeIfPresent(String.self, forKey: .httpUser)
        self.httpPassword = try? container.decodeIfPresent(String.self, forKey: .httpPassword)
        self.secretKey = try? container.decodeIfPresent(String.self, forKey: .secretKey)
        self.multiplexer = try? container.decodeIfPresent(String.self, forKey: .multiplexer)
        self.useEncryption = (try? container.decodeIfPresent(Bool.self, forKey: .useEncryption)) ?? false
        self.useCompression = (try? container.decodeIfPresent(Bool.self, forKey: .useCompression)) ?? false
    }
}

public struct FRPClientConfig: Sendable, Codable {
    public var serverAddr: String
    public var serverPort: Int
    public var user: String
    public var auth: FRPAuthConfig
    public var transport: FRPTransportConfig
    public var loginFailExit: Bool
    public var proxies: [FRPProxyConfig]

    public init(
        serverAddr: String = "127.0.0.1",
        serverPort: Int = 7000,
        user: String = "",
        auth: FRPAuthConfig = FRPAuthConfig(),
        transport: FRPTransportConfig = FRPTransportConfig(),
        loginFailExit: Bool = true,
        proxies: [FRPProxyConfig] = []
    ) {
        self.serverAddr = serverAddr
        self.serverPort = serverPort
        self.user = user
        self.auth = auth
        self.transport = transport
        self.loginFailExit = loginFailExit
        self.proxies = proxies
    }
}
