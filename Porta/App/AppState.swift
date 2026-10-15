import Foundation
import SwiftUI
import Combine

public enum AppScreen: Hashable {
    case main
    case logs
    case settings
}

public enum ActiveSheet: Identifiable {
    case addProxy
    case editProxy(FRPProxy)
    case serverManager
    case addServer
    case editServer(FRPServer)

    public var id: String {
        switch self {
        case .addProxy: return "addProxy"
        case .editProxy(let p): return "editProxy_\(p.id)"
        case .serverManager: return "serverManager"
        case .addServer: return "addServer"
        case .editServer(let s): return "editServer_\(s.id)"
        }
    }
}

public final class AppState: ObservableObject {
    public static let shared = AppState()

    @Published public var currentScreen: AppScreen = .main
    @Published public var activeSheet: ActiveSheet? = nil

    @Published public var servers: [FRPServer] = []
    @Published public var selectedServerId: UUID? = nil
    @Published public var proxies: [FRPProxy] = []
    @Published public var settings: AppSettings = AppSettings()

    public let processManager = FRPProcessManager.shared
    public let logManager = LogManager.shared

    private init() {
        loadData()
    }

    public var currentServer: FRPServer {
        if let id = selectedServerId, let server = servers.first(where: { $0.id == id }) {
            return server
        }
        return servers.first ?? FRPServer(name: "东京服务器")
    }

    public var currentProxies: [FRPProxy] {
        proxies.filter { $0.serverId == nil || $0.serverId == currentServer.id }
    }

    public func loadData() {
        let saved = StorageService.shared.loadData()
        self.servers = saved.servers
        self.proxies = saved.proxies
        self.selectedServerId = saved.selectedServerId ?? saved.servers.first?.id
        self.settings = saved.settings
    }

    public func saveData() {
        StorageService.shared.saveData(
            servers: servers,
            proxies: proxies,
            selectedServerId: selectedServerId,
            settings: settings
        )
    }

    public func selectServer(_ server: FRPServer) {
        self.selectedServerId = server.id
        saveData()

        // Reconnect with new server config if running
        if processManager.isRunning {
            processManager.start(server: server, proxies: currentProxies, settings: settings)
        }
    }

    public func toggleProxy(_ proxy: FRPProxy) {
        if let index = proxies.firstIndex(where: { $0.id == proxy.id }) {
            proxies[index].isEnabled.toggle()
            let updated = proxies[index]
            saveData()
            processManager.notifyProxyToggled(proxy: updated)

            // In real mode, reload configuration
            if processManager.isRunning {
                processManager.start(server: currentServer, proxies: currentProxies, settings: settings)
            }
        }
    }

    public func addProxy(_ proxy: FRPProxy) {
        var newProxy = proxy
        newProxy.serverId = currentServer.id
        proxies.append(newProxy)
        saveData()
        processManager.notifyProxyToggled(proxy: newProxy)
        if processManager.isRunning {
            processManager.start(server: currentServer, proxies: currentProxies, settings: settings)
        }
    }

    public func updateProxy(_ proxy: FRPProxy) {
        if let index = proxies.firstIndex(where: { $0.id == proxy.id }) {
            proxies[index] = proxy
            saveData()
            if processManager.isRunning {
                processManager.start(server: currentServer, proxies: currentProxies, settings: settings)
            }
        }
    }

    public func deleteProxy(_ proxy: FRPProxy) {
        proxies.removeAll { $0.id == proxy.id }
        saveData()
        if processManager.isRunning {
            processManager.start(server: currentServer, proxies: currentProxies, settings: settings)
        }
    }

    public func addServer(_ server: FRPServer) {
        servers.append(server)
        selectedServerId = server.id
        saveData()
        if processManager.isRunning {
            processManager.start(server: server, proxies: currentProxies, settings: settings)
        }
    }

    public func updateServer(_ server: FRPServer) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
            saveData()
            if processManager.isRunning && selectedServerId == server.id {
                processManager.start(server: server, proxies: currentProxies, settings: settings)
            }
        }
    }

    public func deleteServer(_ server: FRPServer) {
        guard servers.count > 1 else { return }
        let wasActive = (selectedServerId == server.id)
        servers.removeAll { $0.id == server.id }
        proxies.removeAll { $0.serverId == server.id }
        if wasActive {
            selectedServerId = servers.first?.id
            if processManager.isRunning {
                processManager.start(server: currentServer, proxies: currentProxies, settings: settings)
            }
        }
        saveData()
    }
}
