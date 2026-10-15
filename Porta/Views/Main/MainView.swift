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

            // Proxy List & Add Button
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
}
