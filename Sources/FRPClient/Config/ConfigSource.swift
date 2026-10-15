import Foundation

public protocol ConfigSource: Sendable {
    func load() throws -> FRPClientConfig
}

public final class MemoryConfigSource: ConfigSource, @unchecked Sendable {
    private let lock = SafeLock()
    private var config: FRPClientConfig

    public init(config: FRPClientConfig) {
        self.config = config
    }

    public func update(config: FRPClientConfig) {
        lock.withLock {
            self.config = config
        }
    }

    public func load() throws -> FRPClientConfig {
        lock.withLock { config }
    }
}

public final class FileConfigSource: ConfigSource, @unchecked Sendable {
    public let filePath: String

    public init(filePath: String) {
        self.filePath = filePath
    }

    public func load() throws -> FRPClientConfig {
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let content = String(data: data, encoding: .utf8) ?? ""
        if content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            return try JSONDecoder().decode(FRPClientConfig.self, from: data)
        } else {
            return try SimpleTOMLParser.parse(content: content)
        }
    }
}

public final class AggregatorConfigSource: ConfigSource, @unchecked Sendable {
    private let lock = SafeLock()
    private var sources: [any ConfigSource] = []

    public init(sources: [any ConfigSource] = []) {
        self.sources = sources
    }

    public func addSource(_ source: any ConfigSource) {
        lock.withLock {
            sources.append(source)
        }
    }

    public func load() throws -> FRPClientConfig {
        let currentSources = lock.withLock { sources }
        guard !currentSources.isEmpty else {
            return FRPClientConfig()
        }

        var baseConfig = try currentSources[0].load()
        var allProxies = baseConfig.proxies
        var proxyNames = Set(allProxies.map { $0.name })

        for s in currentSources.dropFirst() {
            let nextConfig = try s.load()
            for p in nextConfig.proxies {
                if proxyNames.contains(p.name) {
                    throw ValidationError.duplicateProxyName(p.name)
                }
                proxyNames.insert(p.name)
                allProxies.append(p)
            }
        }

        baseConfig.proxies = allProxies
        return baseConfig
    }
}

public final class ConfigWatcher: @unchecked Sendable {
    private let lock = SafeLock()
    private var listeners: [(FRPClientConfig) -> Void] = []
    private var isWatching = false

    public init() {}

    public func watch(_ listener: @escaping (FRPClientConfig) -> Void) -> Int {
        lock.withLock {
            listeners.append(listener)
            isWatching = true
            return listeners.count - 1
        }
    }

    public func unwatch(id: Int) {
        lock.withLock {
            if id >= 0 && id < listeners.count {
                listeners.remove(at: id)
            }
            if listeners.isEmpty {
                isWatching = false
            }
        }
    }

    public var activeWatcherCount: Int {
        lock.withLock { listeners.count }
    }

    public func notifyChange(_ newConfig: FRPClientConfig) {
        let callbacks = lock.withLock { listeners }
        for cb in callbacks {
            cb(newConfig)
        }
    }
}
