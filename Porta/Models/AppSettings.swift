import Foundation

public struct AppSettings: Codable, Equatable {
    // 通用 (General)
    public var launchAtLogin: Bool = true
    public var hideWindowOnLaunch: Bool = true
    public var keepRunningAfterWindowClose: Bool = true

    // 连接 (Connection)
    public var autoReconnect: Bool = true
    public var retryIntervalSeconds: Int = 5
    public var connectTimeoutSeconds: Int = 10

    // 日志 (Logs)
    public var logLevel: String = "Info" // Info, Debug, Warn, Error
    public var logRetention: String = "7 天" // 1 天, 3 天, 7 天, 30 天, 永久
    public var customFrpcPath: String = ""

    // 版本信息
    public static let appVersion: String = "1.0.0"
    public static let frpcVersion: String = "0.65.0 (Swift)"

    public init() {}
}
