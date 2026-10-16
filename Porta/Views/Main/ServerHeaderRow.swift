import SwiftUI

public struct ServerHeaderRow: View {
    @ObservedObject var appState: AppState = .shared
    @ObservedObject var processManager: FRPProcessManager = .shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                // Status dot indicator
                StatusIndicatorDot(
                    status: processManager.status,
                    hasWarning: processManager.status == .connected && processManager.hasProxyErrors,
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
                                    Text(server.name)
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

                    if processManager.isRunning {
                        Button("重新连接") {
                            processManager.start(server: appState.currentServer, proxies: appState.currentProxies, settings: appState.settings)
                        }
                        Button("断开连接") {
                            processManager.stop()
                        }
                    } else {
                        Button("连接服务器") {
                            processManager.start(server: appState.currentServer, proxies: appState.currentProxies, settings: appState.settings)
                        }
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
                    if processManager.status == .connected && processManager.hasProxyErrors {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Color(red: 0.95, green: 0.60, blue: 0.08))
                            Text("已连接 (\(processManager.failedProxiesCount)个异常)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(red: 0.95, green: 0.60, blue: 0.08))
                        }
                        .contentShape(Rectangle())
                    } else {
                        Text(processManager.status.displayText)
                            .font(.system(size: 13))
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                            .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .help(processManager.hasProxyErrors ? "存在代理注册失败，点击查看日志" : "点击查看连接日志")
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 28)
        }
    }
}
