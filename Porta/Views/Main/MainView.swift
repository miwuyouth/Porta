import SwiftUI

public struct MainView: View {
    @ObservedObject var appState: AppState = .shared
    @State private var isAddHovered: Bool = false
    @State private var isLogsHovered: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Window Header (Porta, Settings Gear)
            WindowHeaderView(title: "Porta", showBackButton: false, showGearButton: true)

            // Server Header Row (Green dot, 东京服务器 ⌵, 已连接)
            ServerHeaderRow()

            // Error banner for failed proxies (e.g. port already used)
            if let firstFailed = appState.currentProxies.first(where: {
                $0.isEnabled &&
                !appState.dismissedBannerProxyIds.contains($0.id) &&
                appState.processManager.status(for: $0).isFailed
            }), case .failed(let errMsg) = appState.processManager.status(for: firstFailed) {
                failedProxyBanner(proxy: firstFailed, errorMsg: errMsg)
            }

            // Proxy List or Empty State
            if appState.currentProxies.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(appState.currentProxies) { proxy in
                            ProxyRowView(proxy: proxy)

                            Divider()
                                .padding(.horizontal, 28)
                        }

                        // Add Proxy Button
                        HStack(spacing: 8) {
                            Button(action: {
                                appState.activeSheet = .addProxy
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 13, weight: .semibold))
                                    Text("添加代理")
                                        .font(.system(size: 14, weight: .medium))
                                }
                                .foregroundColor(Color(red: 0.0, green: 0.48, blue: 1.0))
                                .opacity(isAddHovered ? 0.75 : 1.0)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                isAddHovered = hovering
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 14)
                        .padding(.bottom, 16)
                    }
                }
            }

            // Low-key bottom bar with "查看日志"
            Divider()

            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.currentScreen = .logs
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11.5, weight: .medium))
                        Text("查看日志")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(isLogsHovered ? .primary : Color.primary.opacity(0.68))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isLogsHovered = hovering
                }
                .help("查看连接与代理日志")

                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("暂无代理", systemImage: "point.3.connected.trianglepath.dotted")
        } description: {
            Text("当前服务器尚未添加任何代理\n点击下方按钮快速配置本地端口映射")
        } actions: {
            Button(action: {
                appState.activeSheet = .addProxy
            }) {
                Label("添加代理", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func failedProxyBanner(proxy: FRPProxy, errorMsg: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundColor(Color.red)

            VStack(alignment: .leading, spacing: 1.5) {
                Text("代理 [\(proxy.name)] 注册失败")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.red)
                Text(FRPProxyRuntimeStatus.friendlyErrorMessage(errorMsg))
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .lineLimit(1)
            }

            Spacer()

            Button(action: {
                appState.activeSheet = .editProxy(proxy)
            }) {
                Text("修改配置")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                    .cornerRadius(5)
            }
            .buttonStyle(.plain)

            Button(action: {
                appState.showLogs(forProxy: proxy.name)
            }) {
                Text("查看日志")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                    .cornerRadius(5)
            }
            .buttonStyle(.plain)

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    _ = appState.dismissedBannerProxyIds.insert(proxy.id)
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("忽略此提示")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 1.0, green: 0.23, blue: 0.19, opacity: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(red: 1.0, green: 0.23, blue: 0.19, opacity: 0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal, 28)
        .padding(.top, 8)
    }
}
