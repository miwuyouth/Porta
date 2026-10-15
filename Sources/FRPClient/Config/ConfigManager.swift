import Foundation

public struct VisitorConfig: Sendable, Codable, Identifiable {
    public var id: String { name }
    public var name: String
    public var type: FRPProxyType
    public var serverName: String
    public var secretKey: String
    public var bindAddr: String
    public var bindPort: Int

    public init(
        name: String,
        type: FRPProxyType = .stcp,
        serverName: String,
        secretKey: String,
        bindAddr: String = "127.0.0.1",
        bindPort: Int
    ) {
        self.name = name
        self.type = type
        self.serverName = serverName
        self.secretKey = secretKey
        self.bindAddr = bindAddr
        self.bindPort = bindPort
    }
}

public struct ConfigReloadDiff: Equatable, Sendable {
    public var added: [String]
    public var removed: [String]
    public var modified: [String]

    public init(added: [String] = [], removed: [String] = [], modified: [String] = []) {
        self.added = added
        self.removed = removed
        self.modified = modified
    }
}

public final class ConfigManager: @unchecked Sendable {
    private let lock = SafeLock()
    private var clientConfig: FRPClientConfig
    private var proxies: [String: FRPProxyConfig] = [:]
    private var visitors: [String: VisitorConfig] = [:]

    public enum ManagerError: Error, Equatable {
        case proxyAlreadyExists(String)
        case proxyNotFound(String)
        case visitorAlreadyExists(String)
        case visitorNotFound(String)
        case validationFailed(String)
    }

    public init(config: FRPClientConfig) {
        self.clientConfig = config
        for p in config.proxies {
            proxies[p.name] = p
        }
    }

    public var currentConfig: FRPClientConfig {
        lock.withLock {
            var cfg = clientConfig
            cfg.proxies = Array(proxies.values)
            return cfg
        }
    }

    public func getProxy(name: String) -> FRPProxyConfig? {
        lock.withLock { proxies[name] }
    }

    public func getAllProxies() -> [FRPProxyConfig] {
        lock.withLock { Array(proxies.values) }
    }

    public func addProxy(_ proxy: FRPProxyConfig) throws {
        try lock.withLock {
            if proxies[proxy.name] != nil {
                throw ManagerError.proxyAlreadyExists(proxy.name)
            }
            try ConfigValidator.validateProxyConfig(proxy)
            proxies[proxy.name] = proxy
        }
    }

    public func updateProxy(_ proxy: FRPProxyConfig) throws {
        try lock.withLock {
            guard proxies[proxy.name] != nil else {
                throw ManagerError.proxyNotFound(proxy.name)
            }
            try ConfigValidator.validateProxyConfig(proxy)
            proxies[proxy.name] = proxy
        }
    }

    public func removeProxy(name: String) throws {
        try lock.withLock {
            guard proxies[name] != nil else {
                throw ManagerError.proxyNotFound(name)
            }
            proxies.removeValue(forKey: name)
        }
    }

    public func addVisitor(_ visitor: VisitorConfig) throws {
        try lock.withLock {
            if visitors[visitor.name] != nil {
                throw ManagerError.visitorAlreadyExists(visitor.name)
            }
            visitors[visitor.name] = visitor
        }
    }

    public func getVisitor(name: String) -> VisitorConfig? {
        lock.withLock { visitors[name] }
    }

    public func removeVisitor(name: String) throws {
        try lock.withLock {
            guard visitors[name] != nil else {
                throw ManagerError.visitorNotFound(name)
            }
            visitors.removeValue(forKey: name)
        }
    }

    public func calculateDiff(newConfig: FRPClientConfig) -> ConfigReloadDiff {
        lock.withLock {
            calculateDiffUnlocked(newConfig: newConfig)
        }
    }

    private func calculateDiffUnlocked(newConfig: FRPClientConfig) -> ConfigReloadDiff {
        let currentNames = Set(proxies.keys)
        let newProxiesDict = Dictionary(newConfig.proxies.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last })
        let newNames = Set(newProxiesDict.keys)

        let added = Array(newNames.subtracting(currentNames)).sorted()
        let removed = Array(currentNames.subtracting(newNames)).sorted()

        var modified: [String] = []
        for common in currentNames.intersection(newNames) {
            if let oldP = proxies[common], let newP = newProxiesDict[common] {
                if oldP.localPort != newP.localPort || oldP.remotePort != newP.remotePort || oldP.type != newP.type {
                    modified.append(common)
                }
            }
        }

        return ConfigReloadDiff(added: added, removed: removed, modified: modified.sorted())
    }

    public func reload(newConfig: FRPClientConfig) throws -> ConfigReloadDiff {
        try lock.withLock {
            try ConfigValidator.validateClientConfig(newConfig)
            let diff = calculateDiffUnlocked(newConfig: newConfig)
            self.clientConfig = newConfig
            self.proxies.removeAll()
            for p in newConfig.proxies {
                self.proxies[p.name] = p
            }
            return diff
        }
    }
}
