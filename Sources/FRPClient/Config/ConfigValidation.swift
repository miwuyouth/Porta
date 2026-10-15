import Foundation

public enum ValidationError: Error, CustomStringConvertible, LocalizedError, Equatable {
    case emptyServerAddr
    case invalidServerPort(Int)
    case invalidHeartbeatInterval(TimeInterval)
    case invalidHeartbeatTimeout(timeout: TimeInterval, interval: TimeInterval)
    case invalidDialServerTimeout(TimeInterval)
    case emptyAuthToken
    case invalidOIDCConfig(String)
    case invalidProxyName(String, reason: String)
    case invalidLocalPort(Int)
    case invalidRemotePort(Int?)
    case invalidLocalIP(String)
    case missingHTTPDomainOrSubdomain(proxyName: String)
    case invalidDomainName(String)
    case invalidLocationPrefix(String)
    case missingSecretKey(proxyName: String)
    case missingMultiplexer(proxyName: String)
    case invalidBandwidthLimit(String)
    case duplicateProxyName(String)

    public var description: String {
        switch self {
        case .emptyServerAddr:
            return "Server address cannot be empty"
        case .invalidServerPort(let p):
            return "Server port \(p) out of range [1-65535]"
        case .invalidHeartbeatInterval(let i):
            return "Heartbeat interval must be greater than 0, got \(i)"
        case .invalidHeartbeatTimeout(let t, let i):
            return "Heartbeat timeout \(t) must be greater than interval \(i)"
        case .invalidDialServerTimeout(let d):
            return "Dial server timeout must be greater than 0, got \(d)"
        case .emptyAuthToken:
            return "Token auth requires a non-empty token"
        case .invalidOIDCConfig(let msg):
            return "Invalid OIDC auth config: \(msg)"
        case .invalidProxyName(let name, let reason):
            return "Invalid proxy name '\(name)': \(reason)"
        case .invalidLocalPort(let p):
            return "Local port \(p) out of range [1-65535]"
        case .invalidRemotePort(let p):
            return "Remote port \(p ?? -1) out of range [1-65535]"
        case .invalidLocalIP(let ip):
            return "Invalid local IP format '\(ip)'"
        case .missingHTTPDomainOrSubdomain(let name):
            return "Proxy '\(name)' must specify customDomains or subdomain"
        case .invalidDomainName(let d):
            return "Invalid domain name: '\(d)'"
        case .invalidLocationPrefix(let loc):
            return "Location '\(loc)' must start with '/'"
        case .missingSecretKey(let name):
            return "Proxy '\(name)' requires secretKey"
        case .missingMultiplexer(let name):
            return "Proxy '\(name)' requires multiplexer"
        case .invalidBandwidthLimit(let limit):
            return "Invalid bandwidth limit format: '\(limit)'"
        case .duplicateProxyName(let name):
            return "Duplicate proxy name found: '\(name)'"
        }
    }

    public var errorDescription: String? {
        description
    }
}

public enum ConfigValidator {
    private static let proxyNameRegex = try! NSRegularExpression(pattern: "^[a-zA-Z0-9_.-]+$")
    private static let domainRegex = try! NSRegularExpression(pattern: "^(\\*\\.)?[a-zA-Z0-9][-a-zA-Z0-9]*(\\.[a-zA-Z0-9][-a-zA-Z0-9]*)*$")
    private static let bandwidthRegex = try! NSRegularExpression(pattern: "^[1-9][0-9]*(KB|MB|GB|B|kb|mb|gb|b)$")

    public static func validateClientConfig(_ config: FRPClientConfig) throws {
        // Server Address
        let trimmedAddr = config.serverAddr.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedAddr.isEmpty {
            throw ValidationError.emptyServerAddr
        }

        // Server Port
        guard config.serverPort >= 1 && config.serverPort <= 65535 else {
            throw ValidationError.invalidServerPort(config.serverPort)
        }

        // Heartbeat
        guard config.transport.heartbeatInterval > 0 else {
            throw ValidationError.invalidHeartbeatInterval(config.transport.heartbeatInterval)
        }
        guard config.transport.heartbeatTimeout > config.transport.heartbeatInterval else {
            throw ValidationError.invalidHeartbeatTimeout(
                timeout: config.transport.heartbeatTimeout,
                interval: config.transport.heartbeatInterval
            )
        }
        guard config.transport.dialServerTimeout > 0 else {
            throw ValidationError.invalidDialServerTimeout(config.transport.dialServerTimeout)
        }

        // Auth
        if config.auth.method == "token" {
            if config.auth.token.trimmingCharacters(in: .whitespaces).isEmpty {
                throw ValidationError.emptyAuthToken
            }
        }

        // Validate Proxies & check for duplicates
        var seenNames = Set<String>()
        for proxy in config.proxies {
            if seenNames.contains(proxy.name) {
                throw ValidationError.duplicateProxyName(proxy.name)
            }
            seenNames.insert(proxy.name)
            try validateProxyConfig(proxy)
        }
    }

    public static func validateProxyName(_ name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw ValidationError.invalidProxyName(name, reason: "name cannot be empty")
        }
        if trimmed.count > 128 {
            throw ValidationError.invalidProxyName(name, reason: "name length cannot exceed 128 characters")
        }
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        guard proxyNameRegex.firstMatch(in: trimmed, options: [], range: range) != nil else {
            throw ValidationError.invalidProxyName(name, reason: "contains illegal characters")
        }
    }

    public static func validateProxyConfig(_ proxy: FRPProxyConfig) throws {
        try validateProxyName(proxy.name)

        // Local IP
        if proxy.localIP.contains(" ") || proxy.localIP.isEmpty {
            throw ValidationError.invalidLocalIP(proxy.localIP)
        }

        // Local Port
        guard proxy.localPort >= 1 && proxy.localPort <= 65535 else {
            throw ValidationError.invalidLocalPort(proxy.localPort)
        }

        // Remote Port if specified
        if let rp = proxy.remotePort {
            guard rp >= 1 && rp <= 65535 else {
                throw ValidationError.invalidRemotePort(rp)
            }
        }

        switch proxy.type {
        case .tcp:
            break

        case .udp:
            guard let rp = proxy.remotePort, rp >= 1 && rp <= 65535 else {
                throw ValidationError.invalidRemotePort(proxy.remotePort)
            }

        case .http, .https:
            let hasCustomDomain = proxy.customDomains?.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? false
            let hasSubdomain = !(proxy.subdomain?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
            if !hasCustomDomain && !hasSubdomain {
                throw ValidationError.missingHTTPDomainOrSubdomain(proxyName: proxy.name)
            }
            if let domains = proxy.customDomains {
                for d in domains {
                    try validateDomain(d)
                }
            }
            if let locations = proxy.locations {
                for loc in locations {
                    if !loc.hasPrefix("/") {
                        throw ValidationError.invalidLocationPrefix(loc)
                    }
                }
            }

        case .stcp, .sudp, .xtcp:
            guard let sk = proxy.secretKey, !sk.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw ValidationError.missingSecretKey(proxyName: proxy.name)
            }

        case .tcpmux:
            guard let mux = proxy.multiplexer, !mux.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw ValidationError.missingMultiplexer(proxyName: proxy.name)
            }
        }
    }

    public static func validateDomain(_ domain: String) throws {
        let d = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        if d.isEmpty || d.contains(" ") || d.contains("/") {
            throw ValidationError.invalidDomainName(domain)
        }
        let range = NSRange(location: 0, length: d.utf16.count)
        guard domainRegex.firstMatch(in: d, options: [], range: range) != nil else {
            throw ValidationError.invalidDomainName(domain)
        }
    }

    public static func validateBandwidthLimit(_ limit: String) throws {
        let trimmed = limit.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        guard bandwidthRegex.firstMatch(in: trimmed, options: [], range: range) != nil else {
            throw ValidationError.invalidBandwidthLimit(limit)
        }
    }

    public static func validateOIDC(clientID: String, clientSecret: String) throws {
        if clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError.invalidOIDCConfig("clientID cannot be empty")
        }
    }
}
