import Foundation

public final class VhostRouter<T: Sendable>: @unchecked Sendable {
    private let lock = SafeLock()
    private var exactRoutes: [String: T] = [:]
    private var wildcardRoutes: [String: T] = [:] // key is suffix without leading "*."

    public init() {}

    public func addRoute(domain: String, handler: T) {
        lock.withLock {
            let lower = domain.lowercased()
            if lower.hasPrefix("*.") {
                let suffix = String(lower.dropFirst(2))
                wildcardRoutes[suffix] = handler
            } else {
                exactRoutes[lower] = handler
            }
        }
    }

    public func getRoute(host: String) -> T? {
        lock.withLock {
            let lowerHost = host.lowercased()
            // 1. Exact match has priority
            if let h = exactRoutes[lowerHost] {
                return h
            }

            // 2. Wildcard match (*.example.com matches sub.example.com)
            // Sort by suffix length descending so more specific wildcard (*.sub.example.com) matches before (*.example.com)
            let sortedWildcards = wildcardRoutes.sorted { $0.key.count > $1.key.count }
            for (suffix, handler) in sortedWildcards {
                if lowerHost.hasSuffix("." + suffix) {
                    return handler
                }
            }

            return nil
        }
    }
}

public final class PathRouter<T: Sendable>: @unchecked Sendable {
    private let lock = SafeLock()
    private var routes: [(prefix: String, handler: T)] = []

    public init() {}

    public func addRoute(prefix: String, handler: T) {
        lock.withLock {
            routes.append((prefix: prefix, handler: handler))
            // Sort by descending prefix length so longest match wins
            routes.sort { $0.prefix.count > $1.prefix.count }
        }
    }

    public func match(path: String) -> T? {
        lock.withLock {
            for route in routes {
                if path.hasPrefix(route.prefix) {
                    return route.handler
                }
            }
            return nil
        }
    }
}

public struct MetricsSnapshot: Sendable {
    public var connectionCounts: [String: Int64]
    public var bytesIn: [String: Int64]
    public var bytesOut: [String: Int64]

    public init(
        connectionCounts: [String: Int64] = [:],
        bytesIn: [String: Int64] = [:],
        bytesOut: [String: Int64] = [:]
    ) {
        self.connectionCounts = connectionCounts
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }
}

public final class MetricsCollector: @unchecked Sendable {
    private let lock = SafeLock()
    private var connMap: [String: Int64] = [:]
    private var bytesInMap: [String: Int64] = [:]
    private var bytesOutMap: [String: Int64] = [:]

    public init() {}

    public func incrementConnection(proxyName: String) {
        lock.withLock {
            connMap[proxyName, default: 0] += 1
        }
    }

    public func recordTraffic(proxyName: String, bytesIn: Int64, bytesOut: Int64) {
        lock.withLock {
            bytesInMap[proxyName, default: 0] += bytesIn
            bytesOutMap[proxyName, default: 0] += bytesOut
        }
    }

    public func snapshot() -> MetricsSnapshot {
        lock.withLock {
            MetricsSnapshot(
                connectionCounts: connMap,
                bytesIn: bytesInMap,
                bytesOut: bytesOutMap
            )
        }
    }
}

public enum LogPrefixFormatter {
    public static func format(proxyName: String? = nil, runID: String? = nil, message: String) -> String {
        var prefix = ""
        if let run = runID, !run.isEmpty {
            prefix += "[\(run)]"
        }
        if let proxy = proxyName, !proxy.isEmpty {
            prefix += "[\(proxy)]"
        }
        if !prefix.isEmpty {
            return "\(prefix) \(message)"
        }
        return message
    }
}
