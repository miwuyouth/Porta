import SwiftUI

public struct AddProxySheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var appState: AppState = .shared

    public var editingProxy: FRPProxy?

    @State private var name: String = ""
    @State private var type: ProxyType = .tcp
    @State private var iconSymbol: String = "globe"
    @State private var localIP: String = "127.0.0.1"
    @State private var localPort: String = "8080"
    @State private var remotePort: String = "18080"
    @State private var customDomains: String = ""
    @State private var subdomain: String = ""
    @State private var useEncryption: Bool = false
    @State private var useCompression: Bool = false

    let availableIcons = [
        ("globe", "网页 (Globe)"),
        ("terminal", "终端 (Terminal)"),
        ("code", "代码 (Code)"),
        ("server.rack", "服务器 (Server)"),
        ("cylinder", "数据库 (Database)"),
        ("gamecontroller", "游戏 (Game)"),
        ("network", "网络 (Network)")
    ]

    public init(editingProxy: FRPProxy? = nil) {
        self.editingProxy = editingProxy
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(editingProxy == nil ? "添加代理" : "编辑代理")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            // Native Form Layout
            VStack(alignment: .leading, spacing: 14) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                    // Name
                    GridRow {
                        Text("代理名称:")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .gridColumnAlignment(.trailing)

                        TextField("例如：Web 服务", text: $name)
                            .portaTextField()
                            .frame(maxWidth: .infinity)
                    }

                    // Type
                    GridRow {
                        Text("代理类型:")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)

                        Picker("", selection: $type) {
                            ForEach(ProxyType.allCases) { item in
                                Text(item.displayName).tag(item)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Icon
                    GridRow {
                        Text("图标:")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)

                        Picker("", selection: $iconSymbol) {
                            ForEach(availableIcons, id: \.0) { icon in
                                Text(icon.1).tag(icon.0)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Local IP & Port
                    GridRow {
                        Text("本地地址:")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            TextField("127.0.0.1", text: $localIP)
                                .portaTextField()

                            Text(":")
                                .foregroundColor(.secondary)

                            TextField("8080", text: $localPort)
                                .portaTextField()
                                .frame(width: 70)
                        }
                    }

                    // Remote Port or Domains
                    if type == .http || type == .https {
                        GridRow {
                            Text("自定义域名:")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)

                            TextField("例如：dev.example.com", text: $customDomains)
                                .portaTextField()
                        }
                    } else if type == .stcp || type == .xtcp {
                        // STCP / XTCP are point-to-point, remote port is not bound on server
                    } else {
                        GridRow {
                            Text("远程端口:")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)

                            TextField("例如：18080", text: $remotePort)
                                .portaTextField()
                                .frame(width: 100)
                        }
                    }

                    // Advanced options
                    GridRow {
                        Text("高级选项:")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)

                        HStack(spacing: 16) {
                            Toggle("启用加密", isOn: $useEncryption)
                            Toggle("启用压缩", isOn: $useCompression)
                        }
                        .font(.system(size: 12.5))
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Spacer(minLength: 0)

            Divider()

            // Buttons
            HStack(spacing: 12) {
                Spacer()

                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("保存") {
                    saveProxy()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || !isPortValid)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .frame(width: 420, height: 320)
        .background(Color.appBackground)
        .onAppear {
            if let p = editingProxy {
                if p.iconSymbol == "chevron.left.forwardslash.chevron.right" {
                    iconSymbol = "code"
                } else {
                    iconSymbol = p.iconSymbol
                }
                localIP = p.localIP
                localPort = "\(p.localPort)"
                remotePort = p.remotePort.map { "\($0)" } ?? ""
                customDomains = p.customDomains ?? ""
                subdomain = p.subdomain ?? ""
                useEncryption = p.useEncryption
                useCompression = p.useCompression
            }
        }
    }

    private var isPortValid: Bool {
        guard let lp = Int(localPort), lp >= 1 && lp <= 65535 else { return false }
        if type == .http || type == .https || type == .stcp || type == .xtcp {
            return true
        }
        guard let rp = Int(remotePort), rp >= 1 && rp <= 65535 else { return false }
        return true
    }

    private func saveProxy() {
        let lPort = Int(localPort) ?? 8080
        let isHTTP = (type == .http || type == .https)
        let isP2P = (type == .stcp || type == .xtcp)
        let rPort = (isHTTP || isP2P) ? nil : Int(remotePort)
        let cDomains = isHTTP ? (customDomains.isEmpty ? nil : customDomains) : nil
        let sDomain = isHTTP ? (subdomain.isEmpty ? nil : subdomain) : nil

        let targetIcon = iconSymbol == "code" ? "chevron.left.forwardslash.chevron.right" : iconSymbol

        if var existing = editingProxy {
            existing.name = name
            existing.type = type
            existing.iconSymbol = targetIcon
            existing.localIP = localIP.isEmpty ? "127.0.0.1" : localIP
            existing.localPort = lPort
            existing.remotePort = rPort
            existing.customDomains = cDomains
            existing.subdomain = sDomain
            existing.useEncryption = useEncryption
            existing.useCompression = useCompression
            appState.updateProxy(existing)
        } else {
            let newProxy = FRPProxy(
                serverId: appState.currentServer.id,
                name: name,
                type: type,
                iconSymbol: targetIcon,
                localIP: localIP.isEmpty ? "127.0.0.1" : localIP,
                localPort: lPort,
                remotePort: rPort,
                customDomains: cDomains,
                subdomain: sDomain,
                isEnabled: true,
                useEncryption: useEncryption,
                useCompression: useCompression
            )
            appState.addProxy(newProxy)
        }
    }
}
