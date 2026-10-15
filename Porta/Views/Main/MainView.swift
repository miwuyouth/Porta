import SwiftUI

public struct MainView: View {
    @ObservedObject var appState: AppState = .shared
    @State private var isAddHovered: Bool = false

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

                    // Add Proxy Button at bottom
                    HStack(spacing: 8) {
                        Button(action: {
                            appState.activeSheet = .addProxy
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.system(size: 13, weight: .regular))
                                Text("添加代理")
                                    .font(.system(size: 14, weight: .regular))
                            }
                            .foregroundColor(isAddHovered ? .primary : Color(nsColor: .secondaryLabelColor))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            isAddHovered = hovering
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
