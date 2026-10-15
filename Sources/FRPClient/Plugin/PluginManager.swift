import Foundation

public protocol FRPPlugin: Sendable {
    var name: String { get }
}

public struct HTTPProxyPlugin: FRPPlugin, Sendable {
    public let name = "http_proxy"
    public var httpUser: String?
    public var httpPassword: String?

    public init(httpUser: String? = nil, httpPassword: String? = nil) {
        self.httpUser = httpUser
        self.httpPassword = httpPassword
    }
}

public struct StaticFilePlugin: FRPPlugin, Sendable {
    public let name = "static_file"
    public var localPath: String
    public var stripPrefix: String

    public init(localPath: String, stripPrefix: String = "") {
        self.localPath = localPath
        self.stripPrefix = stripPrefix
    }

    /// Resolves requested URL path safely within localPath without escaping.
    public func resolvePath(_ requestPath: String) -> String? {
        var cleanRequest = requestPath
        if !stripPrefix.isEmpty && cleanRequest.hasPrefix(stripPrefix) {
            cleanRequest = String(cleanRequest.dropFirst(stripPrefix.count))
        }
        if !cleanRequest.hasPrefix("/") {
            cleanRequest = "/" + cleanRequest
        }

        let fullURL = URL(fileURLWithPath: localPath).appendingPathComponent(cleanRequest).standardized
        let baseStandardized = URL(fileURLWithPath: localPath).standardized.path
        let basePathWithSlash = baseStandardized.hasSuffix("/") ? baseStandardized : baseStandardized + "/"

        if fullURL.path == baseStandardized || fullURL.path.hasPrefix(basePathWithSlash) {
            return fullURL.path
        }
        return nil // Attempted path traversal
    }
}

public struct UnixDomainSocketPlugin: FRPPlugin, Sendable {
    public let name = "unix_domain_socket"
    public var unixPath: String

    public init(unixPath: String) {
        self.unixPath = unixPath
    }
}

public final class PluginManager: @unchecked Sendable {
    private let lock = SafeLock()
    private var plugins: [String: any FRPPlugin] = [:]

    public init() {}

    public func registerPlugin(_ plugin: any FRPPlugin) {
        lock.withLock {
            plugins[plugin.name] = plugin
        }
    }

    public func getPlugin(name: String) -> (any FRPPlugin)? {
        lock.withLock {
            plugins[name]
        }
    }
}

public enum NatHoleState: Equatable, Sendable {
    case initial
    case discovering
    case ready
    case closed
}

public final class NatHoleSession: @unchecked Sendable {
    public let sid: String
    private let lock = SafeLock()
    private var _state: NatHoleState = .initial
    private var visitorCandidates: [String] = []
    private var clientCandidates: [String] = []

    public init(sid: String = UUID().uuidString) {
        self.sid = sid
    }

    public var state: NatHoleState {
        lock.withLock { _state }
    }

    public func transition(to newState: NatHoleState) {
        lock.withLock {
            _state = newState
        }
    }

    public func updateCandidates(visitor: [String]? = nil, client: [String]? = nil) {
        lock.withLock {
            if let v = visitor { visitorCandidates = v }
            if let c = client { clientCandidates = c }
            if !visitorCandidates.isEmpty && !clientCandidates.isEmpty {
                _state = .ready
            }
        }
    }

    public func getCandidates() -> (visitor: [String], client: [String]) {
        lock.withLock { (visitorCandidates, clientCandidates) }
    }
}

public enum ProxyNaming {
    public static func canonicalName(user: String, proxyName: String) -> String {
        let trimmedUser = user.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedUser.isEmpty {
            return proxyName
        }
        return "\(trimmedUser).\(proxyName)"
    }

    public static func parseCanonicalName(_ name: String) -> (user: String?, proxyName: String) {
        let parts = name.split(separator: ".", maxSplits: 1)
        if parts.count == 2 {
            return (String(parts[0]), String(parts[1]))
        }
        return (nil, name)
    }
}
