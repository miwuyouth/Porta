import Foundation

public enum NetUtilError: Error, Equatable {
    case invalidAddress(String)
    case invalidPort(String)
    case invalidCIDR(String)
}

public enum NetUtil {
    /// Splits "host:port" or "[ipv6]:port" or "host" (using defaultPort).
    public static func splitHostPort(_ address: String, defaultPort: Int = 0) throws -> (host: String, port: Int) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NetUtilError.invalidAddress(address) }

        if trimmed.hasPrefix("[") {
            // IPv6 [host]:port
            guard let closeBracketIndex = trimmed.firstIndex(of: "]") else {
                throw NetUtilError.invalidAddress(address)
            }
            let host = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closeBracketIndex])
            let remainder = trimmed[closeBracketIndex...].dropFirst()
            if remainder.hasPrefix(":") {
                let portStr = String(remainder.dropFirst())
                guard let port = Int(portStr), port >= 1 && port <= 65535 else {
                    throw NetUtilError.invalidPort(portStr)
                }
                return (host, port)
            } else if remainder.isEmpty {
                return (host, defaultPort)
            } else {
                throw NetUtilError.invalidAddress(address)
            }
        }

        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 1 {
            return (String(parts[0]), defaultPort)
        } else if parts.count == 2 {
            let host = String(parts[0])
            let portStr = String(parts[1])
            guard let port = Int(portStr), port >= 1 && port <= 65535 else {
                throw NetUtilError.invalidPort(portStr)
            }
            return (host, port)
        } else {
            // Multiple colons without brackets -> invalid IPv6 address without brackets
            throw NetUtilError.invalidAddress(address)
        }
    }

    public static func isLoopback(_ ip: String) -> Bool {
        let trimmed = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "::1" || trimmed == "localhost" { return true }
        if trimmed.hasPrefix("127.") { return true }
        return false
    }

    public static func isPrivateIP(_ ip: String) -> Bool {
        let trimmed = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        if isLoopback(trimmed) { return true }

        let parts = trimmed.split(separator: ".")
        guard parts.count == 4, let p0 = Int(parts[0]), let p1 = Int(parts[1]) else {
            return false
        }

        // 10.0.0.0/8
        if p0 == 10 { return true }
        // 172.16.0.0/12
        if p0 == 172 && (p1 >= 16 && p1 <= 31) { return true }
        // 192.168.0.0/16
        if p0 == 192 && p1 == 168 { return true }

        return false
    }
}

public struct CIDRMatcher: Sendable {
    private let networkIP: UInt32
    private let mask: UInt32

    public init(cidr: String) throws {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2,
              let prefixLen = Int(parts[1]), prefixLen >= 0 && prefixLen <= 32 else {
            throw NetUtilError.invalidCIDR(cidr)
        }

        let ipStr = String(parts[0])
        guard let ip = CIDRMatcher.ipToUInt32(ipStr) else {
            throw NetUtilError.invalidCIDR(cidr)
        }

        if prefixLen == 0 {
            self.mask = 0
        } else {
            self.mask = UInt32.max << (32 - prefixLen)
        }
        self.networkIP = ip & self.mask
    }

    public func contains(_ ipStr: String) -> Bool {
        guard let ip = CIDRMatcher.ipToUInt32(ipStr) else { return false }
        return (ip & mask) == networkIP
    }

    private static func ipToUInt32(_ ipStr: String) -> UInt32? {
        let parts = ipStr.split(separator: ".")
        guard parts.count == 4 else { return nil }
        var result: UInt32 = 0
        for part in parts {
            guard let byteVal = UInt8(part) else { return nil }
            result = (result << 8) | UInt32(byteVal)
        }
        return result
    }
}

public final class ExponentialBackoff: @unchecked Sendable {
    public let initialInterval: TimeInterval
    public let maxInterval: TimeInterval
    public let multiplier: Double
    private var currentInterval: TimeInterval
    private let lock = SafeLock()

    public init(initialInterval: TimeInterval = 1.0, maxInterval: TimeInterval = 60.0, multiplier: Double = 2.0) {
        self.initialInterval = initialInterval
        self.maxInterval = maxInterval
        self.multiplier = multiplier
        self.currentInterval = initialInterval
    }

    public func nextInterval() -> TimeInterval {
        lock.withLock {
            let result = currentInterval
            currentInterval = min(currentInterval * multiplier, maxInterval)
            return result
        }
    }

    public func reset() {
        lock.withLock {
            currentInterval = initialInterval
        }
    }
}

public final class TokenBucketRateLimiter: @unchecked Sendable {
    private let rate: Double // tokens per second
    private let capacity: Double // burst
    private var tokens: Double
    private var lastRefill: Date
    private let lock = SafeLock()

    public init(rate: Double, burst: Double) {
        self.rate = rate
        self.capacity = burst
        self.tokens = burst
        self.lastRefill = Date()
    }

    public func allow(count: Double = 1.0) -> Bool {
        lock.withLock {
            let now = Date()
            let elapsed = now.timeIntervalSince(lastRefill)
            lastRefill = now

            tokens = min(capacity, tokens + elapsed * rate)
            if tokens >= count {
                tokens -= count
                return true
            }
            return false
        }
    }
}

public enum StringUtil {
    public static func randomString(length: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map { _ in letters.randomElement()! })
    }

    public static func canonicalHeaderKey(_ key: String) -> String {
        let parts = key.split(separator: "-")
        let capitalizedParts = parts.map { part -> String in
            guard let first = part.first else { return "" }
            return String(first).uppercased() + String(part.dropFirst()).lowercased()
        }
        return capitalizedParts.joined(separator: "-")
    }
}
