import SwiftUI

public struct ProxyRowView: View {
    @ObservedObject var appState: AppState = .shared
    public var proxy: FRPProxy
    @State private var isHovered: Bool = false

    public init(proxy: FRPProxy) {
        self.proxy = proxy
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 18) {
            // Icon
            proxyIcon(for: proxy.iconSymbol)
                .frame(width: 32, height: 32)

            // Text stack
            VStack(alignment: .leading, spacing: 3) {
                Text(proxy.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)

                Text(proxy.subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }

            Spacer()

            // Native blue toggle switch
            Toggle("", isOn: Binding(
                get: { proxy.isEnabled },
                set: { _ in appState.toggleProxy(proxy) }
            ))
            .toggleStyle(.switch)
            .tint(Color(red: 0.0, green: 0.48, blue: 1.0))
            .labelsHidden()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color(nsColor: .quaternaryLabelColor).opacity(0.2) : Color.clear)
                .padding(.horizontal, 16)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button("编辑代理...") {
                appState.activeSheet = .editProxy(proxy)
            }

            Button("复制本地地址") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(proxy.localIP):\(proxy.localPort)", forType: .string)
            }

            if let custom = proxy.customDomains, !custom.isEmpty {
                Button("复制域名") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(custom, forType: .string)
                }
            } else if let remote = proxy.remotePort {
                Button("复制远程端口 (:\(remote))") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(":\(remote)", forType: .string)
                }
            }

            Divider()

            Button("删除代理", role: .destructive) {
                appState.deleteProxy(proxy)
            }
        }
    }

    @ViewBuilder
    private func proxyIcon(for symbol: String) -> some View {
        switch symbol {
        case "globe":
            Image(systemName: "globe")
                .font(.system(size: 26, weight: .regular))
                .foregroundColor(Color.primary.opacity(0.85))
        case "terminal":
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.primary.opacity(0.85), lineWidth: 1.6)
                    .frame(width: 28, height: 22)

                HStack(spacing: 1.5) {
                    Text(">")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                    Text("_")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .offset(y: -1)
                }
                .foregroundColor(Color.primary.opacity(0.85))
            }
        case "chevron.left.forwardslash.chevron.right", "code":
            HStack(spacing: 2) {
                Text("<")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                Text("/")
                    .font(.system(size: 16, weight: .regular))
                    .offset(y: -0.5)
                Text(">")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
            }
            .foregroundColor(Color.primary.opacity(0.85))
        default:
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .regular))
                .foregroundColor(Color.primary.opacity(0.85))
        }
    }
}
