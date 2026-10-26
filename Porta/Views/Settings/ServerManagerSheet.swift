import SwiftUI

public struct ServerManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var appState: AppState = .shared
    @ObservedObject var processManager: FRPProcessManager = .shared

    @State private var selectedServer: FRPServer?
    @State private var editingServerId: UUID?

    // Form fields
    @State private var name: String = ""
    @State private var serverAddr: String = ""
    @State private var serverPort: String = "7000"
    @State private var token: String = ""
    @State private var transportProtocol: String = "tcp"
    @State private var tlsEnable: Bool = false
    @State private var isTokenVisible: Bool = false

    let protocols = ["tcp", "kcp", "quic", "websocket", "wss"]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Top Window / Sheet Header
            ZStack {
                Text("服务器")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .frame(height: 38)
            .frame(maxWidth: .infinity)
            .background(Color.appBackground)

            Divider()

            // Main Body: Sidebar + Detail Form
            HStack(spacing: 0) {
                // Left Sidebar
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(appState.servers) { server in
                                serverSidebarRow(server)
                            }
                        }
                        .padding(10)
                    }

                    Divider()

                    // Sidebar Bottom Action Bar
                    HStack {
                        Button(action: startNewServer) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("添加服务器")
                                    .font(.system(size: 12.5))
                            }
                            .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Menu {
                            if let s = selectedServer, s.id != appState.currentServer.id {
                                Button("设为当前服务器") {
                                    saveCurrentEditingServer()
                                    appState.selectServer(s)
                                }
                            }

                            Button("复制服务器配置") {
                                duplicateSelectedServer()
                            }

                            Divider()

                            if selectedServer != nil, appState.servers.count > 1 {
                                Button("删除服务器", role: .destructive) {
                                    deleteSelectedServer()
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 22, height: 22)
                                .portaGlass(in: Circle())
                        }
                        .buttonStyle(.plain)
                        .menuIndicator(.hidden)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(PortaGlass.isAvailable ? Color.clear : Color(nsColor: .controlBackgroundColor))
                }
                .frame(width: PortaGlass.isAvailable ? 226 : 210)
                .portaSidebarBackground()

                Divider()

                // Right Detail Pane
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            // Header
                            VStack(alignment: .leading, spacing: 3) {
                                Text(name.isEmpty ? (selectedServer?.name ?? "服务器") : name)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.primary)

                                Text("配置服务器连接信息")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.bottom, 2)

                            // 名称
                            VStack(alignment: .leading, spacing: 5) {
                                Text("名称")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                TextField("服务器名称", text: $name)
                                    .portaTextField()
                            }

                            // 地址 & 端口
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("地址")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    TextField("例如：frp.example.com", text: $serverAddr)
                                        .portaTextField()
                                }

                                VStack(alignment: .leading, spacing: 5) {
                                    Text("端口")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    TextField("7000", text: $serverPort)
                                        .portaTextField()
                                        .frame(width: 80)
                                }
                            }

                            // 认证 Token
                            VStack(alignment: .leading, spacing: 5) {
                                Text("认证 Token")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)

                                HStack(spacing: 6) {
                                    if isTokenVisible {
                                        TextField("留空则不使用 Token", text: $token)
                                            .textFieldStyle(.plain)
                                            .font(.system(size: 13))
                                    } else {
                                        SecureField("留空则不使用 Token", text: $token)
                                            .textFieldStyle(.plain)
                                            .font(.system(size: 13))
                                    }

                                    Button(action: { isTokenVisible.toggle() }) {
                                        Image(systemName: isTokenVisible ? "eye.slash" : "eye")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .frame(height: 24)
                                .portaGlass(in: RoundedRectangle(cornerRadius: PortaGlass.isAvailable ? 10 : 5), interactive: false)
                            }

                            Divider()
                                .padding(.vertical, 4)

                            // 连接选项
                            VStack(alignment: .leading, spacing: 12) {
                                Text("连接选项")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)

                                // 传输协议
                                HStack {
                                    Text("传输协议")
                                        .font(.system(size: 13))
                                        .foregroundColor(.primary)

                                    Spacer()

                                    Picker("", selection: $transportProtocol) {
                                        ForEach(protocols, id: \.self) { proto in
                                            Text(proto.uppercased()).tag(proto)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 85)
                                }

                                // TLS 加密
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("TLS 加密")
                                            .font(.system(size: 13))
                                            .foregroundColor(.primary)

                                        Text("加密客户端与服务器之间的连接")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Toggle("", isOn: $tlsEnable)
                                        .toggleStyle(.switch)
                                        .tint(Color(red: 0.0, green: 0.48, blue: 1.0))
                                        .labelsHidden()
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 18)
                        .padding(.bottom, 14)
                    }

                    Divider()

                    // Form Bottom Action Bar
                    HStack {
                        Button("设为当前") {
                            saveCurrentEditingServer()
                            if let s = selectedServer {
                                appState.selectServer(s)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(selectedServer?.id == appState.currentServer.id)

                        if let s = selectedServer {
                            Button(appState.isConnectionActive(s) ? "断开连接" : "连接") {
                                saveCurrentEditingServer()
                                appState.toggleConnection(appState.servers.first(where: { $0.id == s.id }) ?? s)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                        }

                        Spacer()

                        Button("完成") {
                            saveCurrentEditingServer()
                            dismiss()
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || serverAddr.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 24)
                    .frame(height: 44)
                    .background(Color.appBackground)
                }
                .frame(maxWidth: .infinity)
                .background(Color.appBackground)
            }
        }
        .frame(
            minWidth: 620,
            idealWidth: 620,
            maxWidth: 1000,
            minHeight: 420,
            idealHeight: 420,
            maxHeight: 800
        )
        .background(Color.appBackground)
        .onAppear {
            if case .addServer = appState.activeSheet {
                startNewServer()
            } else if case .editServer(let server) = appState.activeSheet {
                selectAndLoadServer(server)
            } else {
                selectAndLoadServer(appState.currentServer)
            }
        }
    }

    @ViewBuilder
    private func serverSidebarRow(_ server: FRPServer) -> some View {
        let isSelected = selectedServer?.id == server.id
        let isCurrent = server.id == appState.currentServer.id
        let connectionStatus = processManager.status(forServer: server.id)

        Button(action: {
            if selectedServer?.id != server.id {
                saveCurrentEditingServer()
                selectAndLoadServer(server)
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: "server.rack")
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(server.serverAddr)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 4)

                HStack(spacing: 4) {
                    if connectionStatus != .disconnected {
                        StatusIndicatorDot(status: connectionStatus, size: 6)
                    }

                    if isCurrent {
                        Text("当前")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .portaSelectionBackground(isSelected)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(appState.isConnectionActive(server) ? "断开连接" : "连接") {
                saveCurrentEditingServer()
                appState.toggleConnection(appState.servers.first(where: { $0.id == server.id }) ?? server)
            }
            if !isCurrent {
                Button("设为当前服务器") {
                    saveCurrentEditingServer()
                    appState.selectServer(server)
                }
            }
            Button("复制") {
                saveCurrentEditingServer()
                let dup = FRPServer(
                    name: "\(server.name) 副本",
                    serverAddr: server.serverAddr,
                    serverPort: server.serverPort,
                    token: server.token,
                    transportProtocol: server.transportProtocol,
                    tlsEnable: server.tlsEnable
                )
                appState.addServer(dup)
                selectAndLoadServer(dup)
            }
            if appState.servers.count > 1 {
                Divider()
                Button("删除", role: .destructive) {
                    if isSelected {
                        deleteSelectedServer()
                    } else {
                        appState.deleteServer(server)
                    }
                }
            }
        }
    }

    private func selectAndLoadServer(_ server: FRPServer) {
        selectedServer = server
        editingServerId = server.id
        name = server.name
        serverAddr = server.serverAddr
        serverPort = "\(server.serverPort)"
        token = server.token
        transportProtocol = server.transportProtocol
        tlsEnable = server.tlsEnable
    }

    private func saveCurrentEditingServer() {
        guard let id = editingServerId,
              var s = appState.servers.first(where: { $0.id == id }) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedAddr = serverAddr.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !trimmedAddr.isEmpty else { return }

        s.name = trimmedName
        s.serverAddr = trimmedAddr
        s.serverPort = Int(serverPort) ?? s.serverPort
        s.token = token
        s.transportProtocol = transportProtocol
        s.tlsEnable = tlsEnable
        appState.updateServer(s)
    }

    private func startNewServer() {
        saveCurrentEditingServer()
        let newS = FRPServer(
            name: "新服务器",
            serverAddr: "127.0.0.1",
            serverPort: 7000
        )
        appState.addServer(newS)
        selectAndLoadServer(newS)
    }

    private func duplicateSelectedServer() {
        guard let s = selectedServer else { return }
        saveCurrentEditingServer()
        let dup = FRPServer(
            name: "\(s.name) 副本",
            serverAddr: s.serverAddr,
            serverPort: s.serverPort,
            token: s.token,
            transportProtocol: s.transportProtocol,
            tlsEnable: s.tlsEnable
        )
        appState.addServer(dup)
        selectAndLoadServer(dup)
    }

    private func deleteSelectedServer() {
        guard let s = selectedServer, appState.servers.count > 1 else { return }
        appState.deleteServer(s)
        let next = appState.servers.first(where: { $0.id == appState.currentServer.id }) ?? appState.servers.first
        if let next = next {
            selectAndLoadServer(next)
        }
    }
}
