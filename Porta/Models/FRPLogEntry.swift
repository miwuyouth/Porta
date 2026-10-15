import Foundation
import SwiftUI

public enum FRPLogLevel: String, Codable, CaseIterable, Identifiable {
    case all = "全部级别"
    case debug = "DEBUG"
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"

    public var id: String { rawValue }

    public var displayColor: Color {
        switch self {
        case .all:
            return Color(nsColor: .secondaryLabelColor)
        case .debug:
            return Color(nsColor: .secondaryLabelColor)
        case .info:
            return Color(nsColor: .secondaryLabelColor)
        case .warn:
            return Color.orange
        case .error:
            return Color.red
        }
    }
}

public struct FRPLogEntry: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var timestamp: Date
    public var level: FRPLogLevel
    public var proxyTag: String?
    public var message: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: FRPLogLevel = .info,
        proxyTag: String? = nil,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.proxyTag = proxyTag
        self.message = message
    }

    public var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }

    public var fullDisplayMessage: String {
        if let tag = proxyTag, !tag.isEmpty {
            if message.hasPrefix("[\(tag)]") {
                return message
            }
            return "[\(tag)] \(message)"
        }
        return message
    }
}
