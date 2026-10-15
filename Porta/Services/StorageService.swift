import Foundation

public final class StorageService {
    public static let shared = StorageService()

    private let appSupportURL: URL
    private let configFileURL: URL
    private let logFileURL: URL

    private init() {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.appSupportURL = base.appendingPathComponent("Porta", isDirectory: true)
        self.configFileURL = self.appSupportURL.appendingPathComponent("config.json")
        self.logFileURL = self.appSupportURL.appendingPathComponent("porta.log")

        try? fileManager.createDirectory(at: self.appSupportURL, withIntermediateDirectories: true)
    }

    public var appDirectoryURL: URL {
        appSupportURL
    }

    public var logFilePath: URL {
        logFileURL
    }

    public struct SavedData: Codable {
        public var servers: [FRPServer]
        public var proxies: [FRPProxy]
        public var selectedServerId: UUID?
        public var settings: AppSettings
    }

    public func loadData() -> SavedData {
        if let data = try? Data(contentsOf: configFileURL),
           let saved = try? JSONDecoder().decode(SavedData.self, from: data) {
            return saved
        }

        // Default initial data matching Screenshot 1 exactly
        let defaultServer = FRPServer(
            name: "东京服务器",
            serverAddr: "tokyo.frp.example.com",
            serverPort: 7000,
            token: "porta_secret_key",
            transportProtocol: "tcp",
            tlsEnable: true,
            isDefault: true
        )

        let secondaryServer = FRPServer(
            name: "香港服务器",
            serverAddr: "hk.frp.example.com",
            serverPort: 7000,
            token: "hk_secret_key",
            transportProtocol: "tcp",
            tlsEnable: true,
            isDefault: false
        )

        let proxy1 = FRPProxy(
            serverId: defaultServer.id,
            name: "Web 服务",
            type: .tcp,
            iconSymbol: "globe",
            localIP: "127.0.0.1",
            localPort: 8080,
            remotePort: 18080,
            isEnabled: true
        )

        let proxy2 = FRPProxy(
            serverId: defaultServer.id,
            name: "SSH",
            type: .tcp,
            iconSymbol: "terminal",
            localIP: "127.0.0.1",
            localPort: 22,
            remotePort: 10022,
            isEnabled: true
        )

        let proxy3 = FRPProxy(
            serverId: defaultServer.id,
            name: "开发预览",
            type: .http,
            iconSymbol: "chevron.left.forwardslash.chevron.right",
            localIP: "localhost",
            localPort: 3000,
            customDomains: "dev.example.com",
            isEnabled: true
        )

        return SavedData(
            servers: [defaultServer, secondaryServer],
            proxies: [proxy1, proxy2, proxy3],
            selectedServerId: defaultServer.id,
            settings: AppSettings()
        )
    }

    public func saveData(servers: [FRPServer], proxies: [FRPProxy], selectedServerId: UUID?, settings: AppSettings) {
        let saved = SavedData(
            servers: servers,
            proxies: proxies,
            selectedServerId: selectedServerId,
            settings: settings
        )
        if let encoded = try? JSONEncoder().encode(saved) {
            try? encoded.write(to: configFileURL, options: .atomic)
        }
    }
}
