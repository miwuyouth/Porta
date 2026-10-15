import Foundation

public enum ProxyType: String, Codable, CaseIterable, Identifiable {
    case tcp = "tcp"
    case udp = "udp"
    case http = "http"
    case https = "https"
    case stcp = "stcp"
    case xtcp = "xtcp"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .tcp: return "TCP"
        case .udp: return "UDP"
        case .http: return "HTTP"
        case .https: return "HTTPS"
        case .stcp: return "STCP (安全)"
        case .xtcp: return "XTCP (点对点)"
        }
    }
}

public struct FRPProxy: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var serverId: UUID?
    public var name: String
    public var type: ProxyType
    public var iconSymbol: String
    public var localIP: String
    public var localPort: Int
    public var remotePort: Int?
    public var customDomains: String?
    public var subdomain: String?
    public var isEnabled: Bool
    public var useEncryption: Bool
    public var useCompression: Bool

    public init(
        id: UUID = UUID(),
        serverId: UUID? = nil,
        name: String,
        type: ProxyType = .tcp,
        iconSymbol: String = "network",
        localIP: String = "127.0.0.1",
        localPort: Int = 8080,
        remotePort: Int? = 18080,
        customDomains: String? = nil,
        subdomain: String? = nil,
        isEnabled: Bool = true,
        useEncryption: Bool = false,
        useCompression: Bool = false
    ) {
        self.id = id
        self.serverId = serverId
        self.name = name
        self.type = type
        self.iconSymbol = iconSymbol
        self.localIP = localIP
        self.localPort = localPort
        self.remotePort = remotePort
        self.customDomains = customDomains
        self.subdomain = subdomain
        self.isEnabled = isEnabled
        self.useEncryption = useEncryption
        self.useCompression = useCompression
    }

    /// Display subtitle formatted exactly as in the mockups:
    /// e.g. "127.0.0.1:8080 → :18080"
    /// e.g. "127.0.0.1:22 → :10022"
    /// e.g. "localhost:3000 → dev.example.com"
    public var subtitle: String {
        let left = "\(localIP):\(localPort)"
        if let custom = customDomains, !custom.isEmpty {
            return "\(left) → \(custom)"
        } else if let sub = subdomain, !sub.isEmpty {
            return "\(left) → \(sub)"
        } else if let remote = remotePort {
            return "\(left) → :\(remote)"
        } else {
            return "\(left)"
        }
    }
}
