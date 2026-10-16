import Foundation

public struct AppSettings: Codable, Equatable {
    // 通用 (General)
    public var launchAtLogin: Bool = false
    public var hideWindowOnLaunch: Bool = false
    public var keepRunningAfterWindowClose: Bool = true

    // 连接 (Connection)
    public var autoConnectOnLaunch: Bool = true
    public var autoReconnect: Bool = true
    public var retryIntervalSeconds: Int = 5
    public var connectTimeoutSeconds: Int = 10

    // 日志 (Logs)
    public var logLevel: String = "Info" // Info, Debug, Warn, Error
    public var logRetention: String = "7 天" // 1 天, 3 天, 7 天, 30 天, 永久
    public var customFrpcPath: String = ""

    // 版本信息
    public static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.1"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        if build.isEmpty || build == "1" {
            return version
        }
        return "\(version) (\(build))"
    }
    public static let frpcVersion: String = "0.65.0 (Swift)"

    public init() {}

    enum CodingKeys: CodingKey {
        case launchAtLogin
        case hideWindowOnLaunch
        case keepRunningAfterWindowClose
        case autoConnectOnLaunch
        case autoReconnect
        case retryIntervalSeconds
        case connectTimeoutSeconds
        case logLevel
        case logRetention
        case customFrpcPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        self.hideWindowOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .hideWindowOnLaunch) ?? false
        self.keepRunningAfterWindowClose = try container.decodeIfPresent(Bool.self, forKey: .keepRunningAfterWindowClose) ?? true
        self.autoConnectOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .autoConnectOnLaunch) ?? true
        self.autoReconnect = try container.decodeIfPresent(Bool.self, forKey: .autoReconnect) ?? true
        self.retryIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .retryIntervalSeconds) ?? 5
        self.connectTimeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .connectTimeoutSeconds) ?? 10
        self.logLevel = try container.decodeIfPresent(String.self, forKey: .logLevel) ?? "Info"
        self.logRetention = try container.decodeIfPresent(String.self, forKey: .logRetention) ?? "7 天"
        self.customFrpcPath = try container.decodeIfPresent(String.self, forKey: .customFrpcPath) ?? ""
    }
}
