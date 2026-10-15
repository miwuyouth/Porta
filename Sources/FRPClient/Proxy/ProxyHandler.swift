import Foundation

public protocol ProxyHandler: Sendable {
    var config: FRPProxyConfig { get }
    func makeNewProxyMessage() -> FRPNewProxyMessage
    func handleWorkConn(_ workConn: any AsyncConnection, startMsg: FRPStartWorkConnMessage) async
}

public final class DefaultProxyHandler: ProxyHandler, @unchecked Sendable {
    public let config: FRPProxyConfig
    private let authToken: String?
    private let localDialer: (@Sendable (String, Int) async throws -> any AsyncConnection)?
    private let onLog: (@Sendable (FRPClientLogLevel, String) -> Void)?

    public init(
        config: FRPProxyConfig,
        authToken: String? = nil,
        localDialer: (@Sendable (String, Int) async throws -> any AsyncConnection)? = nil,
        onLog: (@Sendable (FRPClientLogLevel, String) -> Void)? = nil
    ) {
        self.config = config
        self.authToken = authToken
        self.localDialer = localDialer
        self.onLog = onLog
    }

    public func makeNewProxyMessage() -> FRPNewProxyMessage {
        var msg = FRPNewProxyMessage(
            proxyName: config.name,
            proxyType: config.type.rawValue,
            useEncryption: config.useEncryption ? true : nil,
            useCompression: config.useCompression ? true : nil
        )

        switch config.type {
        case .tcp, .udp:
            msg.remotePort = config.remotePort
        case .http, .https:
            msg.customDomains = config.customDomains
            msg.subdomain = config.subdomain
            msg.locations = config.locations
            msg.httpUser = config.httpUser
            msg.httpPwd = config.httpPassword
            msg.hostHeaderRewrite = config.hostHeaderRewrite
        case .stcp, .sudp, .xtcp:
            msg.sk = config.secretKey
        case .tcpmux:
            msg.multiplexer = "httpconnect"
        }

        return msg
    }

    public func handleWorkConn(_ workConn: any AsyncConnection, startMsg: FRPStartWorkConnMessage) async {
        do {
            let activeWorkConn: any AsyncConnection
            if config.useEncryption {
                let encToken = (config.secretKey?.isEmpty == false ? config.secretKey : authToken) ?? ""
                activeWorkConn = CryptoConnection(wrapping: workConn, token: encToken)
            } else {
                activeWorkConn = workConn
            }

            let localConn: any AsyncConnection
            if let dialer = localDialer {
                localConn = try await dialer(config.localIP, config.localPort)
            } else {
                localConn = try await NWAsyncConnection.connect(
                    host: config.localIP,
                    port: config.localPort,
                    timeout: 10
                )
            }

            // Start bidirectional pump
            await StreamBridge.bridge(activeWorkConn, localConn)
        } catch {
            let errorMsg = "连接本地服务 \(config.localIP):\(config.localPort) 失败: \(error)"
            onLog?(.warn, errorMsg)
            print("[Proxy \(config.name)] \(errorMsg)")
            workConn.close()
        }
    }
}
