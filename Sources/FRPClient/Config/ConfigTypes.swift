import Foundation

public enum PortRangeParser {
    public enum ParseError: Error, Equatable {
        case invalidFormat(String)
        case portOutOfRange(Int)
        case invalidRange(start: Int, end: Int)
    }

    /// Parses strings like "80", "6000-6005", "80,443,6000-6002" into sorted unique ports.
    public static func parse(_ input: String) throws -> [Int] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var resultSet = Set<Int>()
        let parts = trimmed.split(separator: ",")

        for part in parts {
            let item = part.trimmingCharacters(in: .whitespaces)
            if item.contains("-") {
                let rangeComponents = item.split(separator: "-")
                guard rangeComponents.count == 2,
                      let start = Int(rangeComponents[0].trimmingCharacters(in: .whitespaces)),
                      let end = Int(rangeComponents[1].trimmingCharacters(in: .whitespaces)) else {
                    throw ParseError.invalidFormat(item)
                }
                guard start >= 1 && start <= 65535 else { throw ParseError.portOutOfRange(start) }
                guard end >= 1 && end <= 65535 else { throw ParseError.portOutOfRange(end) }
                guard start <= end else { throw ParseError.invalidRange(start: start, end: end) }

                for port in start...end {
                    resultSet.insert(port)
                }
            } else {
                guard let port = Int(item) else {
                    throw ParseError.invalidFormat(item)
                }
                guard port >= 1 && port <= 65535 else {
                    throw ParseError.portOutOfRange(port)
                }
                resultSet.insert(port)
            }
        }

        return resultSet.sorted()
    }
}

public enum DurationParser {
    public enum ParseError: Error, Equatable {
        case invalidFormat(String)
    }

    /// Parses Go-style duration strings into TimeInterval (seconds):
    /// "30s", "1m", "2h", "500ms"
    public static func parse(_ input: String) throws -> TimeInterval {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ParseError.invalidFormat(input)
        }

        if trimmed.hasSuffix("ms") {
            let numStr = String(trimmed.dropLast(2))
            guard let val = Double(numStr), val >= 0 else { throw ParseError.invalidFormat(input) }
            return val / 1000.0
        } else if trimmed.hasSuffix("s") {
            let numStr = String(trimmed.dropLast(1))
            guard let val = Double(numStr), val >= 0 else { throw ParseError.invalidFormat(input) }
            return val
        } else if trimmed.hasSuffix("m") {
            let numStr = String(trimmed.dropLast(1))
            guard let val = Double(numStr), val >= 0 else { throw ParseError.invalidFormat(input) }
            return val * 60.0
        } else if trimmed.hasSuffix("h") {
            let numStr = String(trimmed.dropLast(1))
            guard let val = Double(numStr), val >= 0 else { throw ParseError.invalidFormat(input) }
            return val * 3600.0
        }

        throw ParseError.invalidFormat(input)
    }
}

public enum BandwidthParser {
    public enum ParseError: Error, Equatable {
        case invalidFormat(String)
    }

    /// Parses bandwidth strings like "10KB", "5MB", "1GB", "1024B" into bytes (Int64).
    public static func parseBytes(_ input: String) throws -> Int64 {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { throw ParseError.invalidFormat(input) }

        var multiplier: Int64 = 1
        var numStr = trimmed

        if trimmed.hasSuffix("GB") {
            multiplier = 1024 * 1024 * 1024
            numStr = String(trimmed.dropLast(2))
        } else if trimmed.hasSuffix("MB") {
            multiplier = 1024 * 1024
            numStr = String(trimmed.dropLast(2))
        } else if trimmed.hasSuffix("KB") {
            multiplier = 1024
            numStr = String(trimmed.dropLast(2))
        } else if trimmed.hasSuffix("B") {
            multiplier = 1
            numStr = String(trimmed.dropLast(1))
        } else {
            throw ParseError.invalidFormat(input)
        }

        guard let val = Int64(numStr), val > 0 else {
            throw ParseError.invalidFormat(input)
        }

        return val * multiplier
    }
}

public enum EnvExpander {
    /// Expands template strings like `{{ .Envs.FRP_SERVER_ADDR }}` or `{{ .Envs.PORT | default "7000" }}`
    public static func expand(_ template: String, env: [String: String] = ProcessInfo.processInfo.environment) -> String {
        var result = template
        let pattern = "\\{\\{\\s*\\.Envs\\.([a-zA-Z0-9_]+)(\\s*\\|\\s*default\\s+\"([^\"]+)\")?\\s*\\}\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return template }

        let nsString = template as NSString
        let matches = regex.matches(in: template, range: NSRange(location: 0, length: nsString.length))

        for match in matches.reversed() {
            let varRange = match.range(at: 1)
            let varName = nsString.substring(with: varRange)

            var replacement = env[varName]
            if replacement == nil && match.numberOfRanges > 3 && match.range(at: 3).location != NSNotFound {
                replacement = nsString.substring(with: match.range(at: 3))
            }

            if let rep = replacement {
                result = (result as NSString).replacingCharacters(in: match.range, with: rep)
            }
        }
        return result
    }
}
