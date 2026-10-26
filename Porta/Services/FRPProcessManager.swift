import Foundation
import Combine
import UserNotifications

public enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    public var displayText: String {
        switch self {
        case .disconnected: return "未连接"
        case .connecting: return "连接中..."
        case .connected: return "已连接"
        case .error(let msg): return "连接失败: \(msg)"
        }
    }
}

/// One independent connection to a single FRP server.
private final class ServerSession: @unchecked Sendable {
    var server: FRPServer
    var proxies: [FRPProxy]
    var settings: AppSettings
    var logPrefix: String = ""

    var isExplicitlyStopped: Bool = false
    var reconnectWorkItem: DispatchWorkItem?
    var proxyNameToId: [String: UUID] = [:]

    // Native pure Swift FRP client
    var clientService: FRPClientService?
    var serviceTask: Task<Void, Never>?

    // Optional external process override (if user specified customFrpcPath)
    var process: Process?
    var stdoutPipe: Pipe?

    init(server: FRPServer, proxies: [FRPProxy], settings: AppSettings) {
        self.server = server
        self.proxies = proxies
        self.settings = settings
    }
}

/// Manages one connection per server, so several servers can be online at the same time.
public final class FRPProcessManager: ObservableObject, @unchecked Sendable {
    public static let shared = FRPProcessManager()

    /// Connection status per server id. A missing entry means disconnected.
    @Published public private(set) var serverStatuses: [UUID: ConnectionStatus] = [:]
    /// Servers the user has started and not explicitly stopped (includes ones currently retrying).
    @Published public private(set) var activeServerIds: Set<UUID> = []
    @Published public var proxyStatuses: [UUID: FRPProxyRuntimeStatus] = [:]

    private var sessions: [UUID: ServerSession] = [:]

    private init() {}

    // MARK: - Server state

    public func status(forServer id: UUID) -> ConnectionStatus {
        serverStatuses[id] ?? .disconnected
    }

    public func isActive(serverId id: UUID) -> Bool {
        activeServerIds.contains(id)
    }

    public var hasActiveServers: Bool {
        !activeServerIds.isEmpty
    }

    public var connectedServerCount: Int {
        serverStatuses.values.filter { $0 == .connected }.count
    }

    private func setStatus(_ status: ConnectionStatus, for session: ServerSession) {
        serverStatuses[session.server.id] = status
    }

    private func log(_ session: ServerSession, _ level: FRPLogLevel, tag: String? = nil, _ message: String) {
        LogManager.shared.add(level: level, proxyTag: tag, message: session.logPrefix + message)
    }

    // MARK: - Start / stop

    /// Starts (or restarts) the connection for `server`. Other servers are left untouched.
    public func start(server: FRPServer, proxies: [FRPProxy], settings: AppSettings) {
        let session = sessions[server.id] ?? ServerSession(server: server, proxies: proxies, settings: settings)
        sessions[server.id] = session

        session.reconnectWorkItem?.cancel()
        session.reconnectWorkItem = nil

        stopInternal(session)

        session.isExplicitlyStopped = false
        session.server = server
        session.proxies = proxies
        session.settings = settings
        session.logPrefix = AppState.shared.servers.count > 1 ? "[\(server.name)] " : ""
        activeServerIds.insert(server.id)

        session.proxyNameToId.removeAll()
        for p in proxies {
            let safeName = FRPConfigGenerator.sanitizeProxyName(p.name)
            session.proxyNameToId[safeName] = p.id
            session.proxyNameToId[p.name] = p.id
            proxyStatuses[p.id] = p.isEnabled ? .registering : .stopped
        }

        setStatus(.connecting, for: session)
        log(session, .info, "正在启动 Swift 原生 FRP 引擎...")

        // Always generate a per-server frpc config for persistence and reference
        let configString = FRPConfigGenerator.generateToml(server: server, proxies: proxies, settings: settings)
        let configURL = StorageService.shared.appDirectoryURL.appendingPathComponent("frpc_\(server.id.uuidString).toml")
        try? configString.write(to: configURL, atomically: true, encoding: .utf8)

        // Check if user explicitly provided a custom frpc binary override
        if !settings.customFrpcPath.isEmpty && FileManager.default.isExecutableFile(atPath: settings.customFrpcPath) {
            startExternalProcess(session, binaryPath: settings.customFrpcPath, configURL: configURL)
            return
        }

        // Native Pure Swift FRP Client Mode
        startNativeClient(session)
    }

    private func startNativeClient(_ session: ServerSession) {
        let server = session.server
        let settings = session.settings
        let activeProxies = session.proxies.filter { $0.isEnabled }

        let proxyConfigs: [FRPProxyConfig] = activeProxies.map { proxy in
            let proxyType: FRPProxyType
            switch proxy.type {
            case .tcp: proxyType = .tcp
            case .udp: proxyType = .udp
            case .http: proxyType = .http
            case .https: proxyType = .https
            case .stcp: proxyType = .stcp
            case .xtcp: proxyType = .xtcp
            }

            let domains = proxy.customDomains?
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            let safeName = FRPConfigGenerator.sanitizeProxyName(proxy.name)
            let secretKey = (proxyType == .stcp || proxyType == .xtcp) ? server.token : nil

            return FRPProxyConfig(
                name: safeName,
                type: proxyType,
                localIP: proxy.localIP.isEmpty ? "127.0.0.1" : proxy.localIP,
                localPort: proxy.localPort,
                remotePort: (proxyType == .http || proxyType == .https) ? nil : proxy.remotePort,
                customDomains: domains,
                subdomain: proxy.subdomain?.trimmingCharacters(in: .whitespaces).isEmpty == false ? proxy.subdomain : nil,
                secretKey: secretKey,
                useEncryption: proxy.useEncryption,
                useCompression: proxy.useCompression
            )
        }

        let transport = FRPTransportConfig(
            protocolType: server.transportProtocol,
            tcpMux: true,
            tlsEnable: server.tlsEnable,
            heartbeatInterval: 30,
            heartbeatTimeout: 90,
            dialServerTimeout: TimeInterval(settings.connectTimeoutSeconds)
        )

        let auth = FRPAuthConfig(
            method: "token",
            token: server.token
        )

        let clientConfig = FRPClientConfig(
            serverAddr: server.serverAddr,
            serverPort: server.serverPort,
            user: "",
            auth: auth,
            transport: transport,
            loginFailExit: false,
            proxies: proxyConfigs
        )

        let service = FRPClientService(
            config: clientConfig,
            onLog: { [weak self, weak session] level, tag, message in
                guard let session = session else { return }
                let logLevel: FRPLogLevel
                switch level {
                case .debug: logLevel = .debug
                case .info: logLevel = .info
                case .warn: logLevel = .warn
                case .error: logLevel = .error
                }
                let cleanTag = tag.flatMap { self?.tagForProxyName($0) }
                self?.log(session, logLevel, tag: cleanTag, message)
            },
            onStatusChange: { [weak self, weak session] isConnected, errorMsg in
                DispatchQueue.main.async {
                    guard let self = self, let session = session, !session.isExplicitlyStopped else { return }
                    if isConnected {
                        self.setStatus(.connected, for: session)
                    } else if let err = errorMsg {
                        self.setStatus(.error(err), for: session)
                        self.scheduleReconnect(session)
                    } else {
                        self.setStatus(.disconnected, for: session)
                        self.scheduleReconnect(session)
                    }
                }
            },
            onProxyStatusChange: { [weak self, weak session] proxyName, proxyStatus in
                DispatchQueue.main.async {
                    guard let self = self, let session = session else { return }
                    self.updateProxyStatus(session, proxyName: proxyName, runtimeStatus: proxyStatus)
                }
            }
        )

        session.clientService = service

        session.serviceTask = Task { [weak self, weak service, weak session] in
            guard let self = self, let session = session else { return }
            do {
                try await service?.start()
                guard !Task.isCancelled, !session.isExplicitlyStopped else { return }
                await MainActor.run {
                    self.setStatus(.connected, for: session)
                }
            } catch {
                guard !Task.isCancelled, !session.isExplicitlyStopped else { return }
                await MainActor.run {
                    self.setStatus(.error(error.localizedDescription), for: session)
                    self.scheduleReconnect(session)
                }
                self.log(session, .error, "启动失败: \(error.localizedDescription)")
            }
        }
    }

    private func startExternalProcess(_ session: ServerSession, binaryPath: String, configURL: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binaryPath)
        p.arguments = ["-c", configURL.path]

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self, weak session] handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8), let session = session else { return }
            self?.parseRealFrpLog(session, line)
        }

        p.terminationHandler = { [weak self, weak session] proc in
            DispatchQueue.main.async {
                // Ignore exits of a process that was already replaced or stopped on purpose
                guard let self = self, let session = session, session.process === proc else { return }
                self.setStatus(.disconnected, for: session)
                self.log(session, .warn, "FRP 进程已退出 (code: \(proc.terminationStatus))")
                self.scheduleReconnect(session)
            }
        }

        do {
            try p.run()
            session.process = p
            session.stdoutPipe = pipe
            setStatus(.connecting, for: session)
            log(session, .info, "FRP 外部客户端已启动 (PID: \(p.processIdentifier))")
        } catch {
            setStatus(.error(error.localizedDescription), for: session)
            log(session, .error, "启动失败: \(error.localizedDescription)")
        }
    }

    private func stopInternal(_ session: ServerSession) {
        session.serviceTask?.cancel()
        session.serviceTask = nil

        let svc = session.clientService
        session.clientService = nil

        Task {
            await svc?.detachCallbacks()
            await svc?.stop()
        }

        let p = session.process
        session.process = nil
        if let p = p, p.isRunning {
            p.terminate()
        }
        session.stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        session.stdoutPipe = nil

        for proxy in session.proxies {
            proxyStatuses[proxy.id] = .stopped
        }

        setStatus(.disconnected, for: session)
    }

    /// Disconnects a single server.
    public func stop(serverId: UUID) {
        guard let session = sessions[serverId] else { return }
        session.isExplicitlyStopped = true
        session.reconnectWorkItem?.cancel()
        session.reconnectWorkItem = nil
        activeServerIds.remove(serverId)

        stopInternal(session)
        sessions[serverId] = nil
        serverStatuses[serverId] = nil
        log(session, .info, "已断开连接")
    }

    /// Disconnects every server.
    public func stopAll() {
        for id in Array(sessions.keys) {
            stop(serverId: id)
        }
    }

    private func scheduleReconnect(_ session: ServerSession) {
        guard !session.isExplicitlyStopped, session.settings.autoReconnect else { return }
        session.reconnectWorkItem?.cancel()
        let interval = max(1, session.settings.retryIntervalSeconds)
        log(session, .warn, "\(interval) 秒后尝试自动重新连接...")

        let item = DispatchWorkItem { [weak self, weak session] in
            guard let self = self, let session = session, !session.isExplicitlyStopped else { return }
            self.start(server: session.server, proxies: session.proxies, settings: session.settings)
        }
        session.reconnectWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(interval), execute: item)
    }

    public func notifyProxyToggled(proxy: FRPProxy) {
        let tag = tagForProxyName(proxy.name)
        if proxy.isEnabled {
            LogManager.shared.add(level: .info, proxyTag: tag, message: "代理已启用")
        } else {
            proxyStatuses[proxy.id] = .stopped
            LogManager.shared.add(level: .info, proxyTag: tag, message: "代理已停止")
        }
    }

    public func tagForProxyName(_ name: String) -> String {
        FRPConfigGenerator.sanitizeProxyName(name)
    }

    public func status(for proxy: FRPProxy) -> FRPProxyRuntimeStatus {
        guard proxy.isEnabled, let serverId = proxy.serverId else { return .stopped }
        switch serverStatuses[serverId] {
        case .connecting, .connected:
            return proxyStatuses[proxy.id] ?? .stopped
        default:
            return .stopped
        }
    }

    public func failedProxies(serverId: UUID) -> [FRPProxy] {
        AppState.shared.proxies.filter { proxy in
            proxy.serverId == serverId && proxy.isEnabled && (proxyStatuses[proxy.id]?.isFailed == true)
        }
    }

    public func failedProxiesCount(serverId: UUID) -> Int {
        failedProxies(serverId: serverId).count
    }

    public func hasProxyErrors(serverId: UUID) -> Bool {
        !failedProxies(serverId: serverId).isEmpty
    }

    private func updateProxyStatus(_ session: ServerSession, proxyName: String, runtimeStatus: FRPProxyRuntimeStatus) {
        let matchedId = session.proxyNameToId[proxyName] ?? session.proxies.first(where: {
            tagForProxyName($0.name) == proxyName || $0.name == proxyName || $0.name.lowercased() == proxyName.lowercased()
        })?.id

        if let id = matchedId {
            proxyStatuses[id] = runtimeStatus

            if case .failed(let err) = runtimeStatus {
                let displayName = session.proxies.first(where: { $0.id == id })?.name ?? proxyName
                sendErrorNotificationIfNeeded(proxyName: displayName, error: err)
            }
        }
    }

    private func sendErrorNotificationIfNeeded(proxyName: String, error: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = "Porta 代理注册失败"
            content.subtitle = "代理 [\(proxyName)]"
            content.body = FRPProxyRuntimeStatus.friendlyErrorMessage(error)
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "proxy_error_\(proxyName)_\(Date().timeIntervalSince1970)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }

    private func parseRealFrpLog(_ session: ServerSession, _ output: String) {
        let ansiPattern = #"\x1B\[[0-9;]*[a-zA-Z]"#
        let ansiRegex = try? NSRegularExpression(pattern: ansiPattern)

        let lines = output.components(separatedBy: .newlines)
        for rawLine in lines {
            var line = rawLine
            if let regex = ansiRegex {
                let range = NSRange(location: 0, length: line.utf16.count)
                line = regex.stringByReplacingMatches(in: line, range: range, withTemplate: "")
            }
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if line.isEmpty || line == "[0m" || line == "[m" {
                continue
            }

            var level: FRPLogLevel = .info
            var displayMessage = line
            var proxyTag: String? = nil

            let frpLogPattern = #"^(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}(?:\.\d{3})?)\s+\[([A-Z])\]\s*(.*)$"#
            var matchedFormat = false
            if let regex = try? NSRegularExpression(pattern: frpLogPattern) {
                let nsLine = line as NSString
                let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
                if let match = matches.first, match.numberOfRanges >= 4 {
                    matchedFormat = true
                    let levelChar = nsLine.substring(with: match.range(at: 2))
                    let content = nsLine.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)

                    switch levelChar {
                    case "W": level = .warn
                    case "E": level = .error
                    case "D": level = .debug
                    default: level = .info
                    }

                    displayMessage = content
                }
            }
            if !matchedFormat {
                let lower = line.lowercased()
                if lower.contains("error") || lower.contains("failed") || lower.contains("fatal") {
                    level = .error
                } else if lower.contains("warn") {
                    level = .warn
                }
            }

            for proxy in session.proxies {
                let tag = tagForProxyName(proxy.name)
                if displayMessage.contains("[\(tag)]") || displayMessage.contains("[\(proxy.name)]") {
                    proxyTag = tag
                    break
                }
            }

            if let matchedProxy = session.proxies.first(where: {
                let tag = tagForProxyName($0.name)
                return displayMessage.contains("[\(tag)]") || displayMessage.contains("[\($0.name)]")
            }) {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if displayMessage.contains("start error:") {
                        let errMsg: String
                        if let range = displayMessage.range(of: "start error:") {
                            errMsg = String(displayMessage[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                        } else {
                            errMsg = displayMessage
                        }
                        self.updateProxyStatus(session, proxyName: matchedProxy.name, runtimeStatus: .failed(error: errMsg))
                    } else if displayMessage.contains("start proxy success") {
                        self.updateProxyStatus(session, proxyName: matchedProxy.name, runtimeStatus: .running(remoteAddr: nil))
                    }
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if displayMessage.contains("login to server success") || displayMessage.contains("start proxy success") {
                    self.setStatus(.connected, for: session)
                } else if displayMessage.contains("login to the server failed") || displayMessage.contains("connect to server error") {
                    self.setStatus(.error("连接失败"), for: session)
                }
            }

            log(session, level, tag: proxyTag, displayMessage)
        }
    }
}
