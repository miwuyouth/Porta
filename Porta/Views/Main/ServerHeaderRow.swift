import SwiftUI

public struct ServerHeaderRow: View {
    @ObservedObject var appState: AppState = .shared
    @ObservedObject var processManager: FRPProcessManager = .shared

    public init() {}

    private var server: FRPServer { appState.currentServer }
    private var status: ConnectionStatus { processManager.status(forServer: server.id) }
    private var hasProxyErrors: Bool { processManager.hasProxyErrors(serverId: server.id) }

    private func menuTitle(for server: FRPServer) -> String {
        switch processManager.status(forServer: server.id) {
        case .connected: return "\(server.name) · 已连接"
        case .connecting: return "\(server.name) · 连接中..."
        case .error: return "\(server.name) · 连接失败"
        case .disconnected: return server.name
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                // Status dot indicator
                StatusIndicatorDot(
                    status: status,
                    hasWarning: status == .connected && hasProxyErrors,
                    size: 8
                )

                // Server name dropdown Menu
                Menu {
                    Section("选择服务器") {
                        ForEach(appState.servers) { server in
                            Button(action: {
                                appState.selectServer(server)
                            }) {
                                HStack {
                                    Text(menuTitle(for: server))
                                    if server.id == appState.currentServer.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }

                    Divider()

                    Button("添加服务器...") {
                        appState.activeSheet = .addServer
                    }

                    Button("管理服务器...") {
                        appState.activeSheet = .serverManager
                    }

                    Divider()

                    if appState.isConnectionActive(server) {
                        Button("重新连接") {
                            appState.connect(server)
                        }
                        Button("断开连接") {
                            appState.disconnect(server)
                        }
                    } else {
                        Button("连接服务器") {
                            appState.connect(server)
                        }
                    }

                    if appState.servers.count > 1 {
                        Divider()

                        Button("连接全部服务器") {
                            appState.connectAll()
                        }
                        Button("断开全部连接") {
                            appState.disconnectAll()
                        }
                        .disabled(!processManager.hasActiveServers)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(appState.currentServer.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()

                Spacer()

                // Status text on right (e.g. "已连接" or "已连接 (1个异常)")
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.currentScreen = .logs
                    }
                }) {
                    if status == .connected && hasProxyErrors {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Color(red: 0.95, green: 0.60, blue: 0.08))
                            Text("已连接 (\(processManager.failedProxiesCount(serverId: server.id))个异常)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(red: 0.95, green: 0.60, blue: 0.08))
                        }
                        .contentShape(Rectangle())
                    } else {
                        Text(status.displayText)
                            .font(.system(size: 13))
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                            .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .help(hasProxyErrors ? "存在代理注册失败，点击查看日志" : "点击查看连接日志")
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 28)
        }
    }
}
