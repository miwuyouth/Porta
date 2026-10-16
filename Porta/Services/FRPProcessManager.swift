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

public final class FRPProcessManager: ObservableObject, @unchecked Sendable {
    public static let shared = FRPProcessManager()

    @Published public var status: ConnectionStatus = .disconnected
    @Published public var isRunning: Bool = false
    @Published public var proxyStatuses: [UUID: FRPProxyRuntimeStatus] = [:]

    // Native pure Swift FRP client
    private var clientService: FRPClientService?
    private var serviceTask: Task<Void, Never>?

    // Auto-reconnect & state management
    private var lastServer: FRPServer?
    private var lastProxies: [FRPProxy] = []
    private var lastSettings: AppSettings?
    private var isExplicitlyStopped: Bool = true
    private var reconnectWorkItem: DispatchWorkItem?
    private var proxyNameToId: [String: UUID] = [:]

    // Optional external process override (if user specified customFrpcPath)
    private var process: Process?
    private var stdoutPipe: Pipe?

    private init() {
        self.status = .disconnected
        self.isRunning = false
    }

    public func start(server: FRPServer, proxies: [FRPProxy], settings: AppSettings) {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        isExplicitlyStopped = false

        lastServer = server
        lastProxies = proxies
        lastSettings = settings

        stopInternal()

        proxyNameToId.removeAll()
        for p in proxies {
            let safeName = FRPConfigGenerator.sanitizeProxyName(p.name)
            proxyNameToId[safeName] = p.id
            proxyNameToId[p.name] = p.id
            if p.isEnabled {
                proxyStatuses[p.id] = .registering
            } else {
                proxyStatuses[p.id] = .stopped
            }
        }

        status = .connecting
        LogManager.shared.add(level: .info, proxyTag: nil, message: "正在启动 Swift 原生 FRP 引擎...")

        // Always generate frpc.toml for config persistence and reference
        let configString = FRPConfigGenerator.generateToml(server: server, proxies: proxies, settings: settings)
        let configURL = StorageService.shared.appDirectoryURL.appendingPathComponent("frpc.toml")
        try? configString.write(to: configURL, atomically: true, encoding: .utf8)

        // Check if user explicitly provided a custom frpc binary override
        if !settings.customFrpcPath.isEmpty && FileManager.default.isExecutableFile(atPath: settings.customFrpcPath) {
            startExternalProcess(binaryPath: settings.customFrpcPath, configURL: configURL)
            return
        }

        // Native Pure Swift FRP Client Mode
        startNativeClient(server: server, proxies: proxies, settings: settings)
    }

    private func startNativeClient(server: FRPServer, proxies: [FRPProxy], settings: AppSettings) {
        let activeProxies = proxies.filter { $0.isEnabled }

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
            onLog: { [weak self] level, tag, message in
                let logLevel: FRPLogLevel
                switch level {
                case .debug: logLevel = .debug
                case .info: logLevel = .info
                case .warn: logLevel = .warn
                case .error: logLevel = .error
                }
                let cleanTag = tag.flatMap { self?.tagForProxyName($0) }
                LogManager.shared.add(level: logLevel, proxyTag: cleanTag, message: message)
            },
            onStatusChange: { [weak self] isConnected, errorMsg in
                DispatchQueue.main.async {
                    guard let self = self, !self.isExplicitlyStopped else { return }
                    if isConnected {
                        self.isRunning = true
                        self.status = .connected
                    } else if let err = errorMsg {
                        self.isRunning = false
                        self.status = .error(err)
                        self.scheduleReconnect()
                    } else {
                        self.isRunning = false
                        self.status = .disconnected
                        self.scheduleReconnect()
                    }
                }
            },
            onProxyStatusChange: { [weak self] proxyName, proxyStatus in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.updateProxyStatus(proxyName: proxyName, runtimeStatus: proxyStatus)
                }
            }
        )

        self.clientService = service
        self.isRunning = true

        self.serviceTask = Task { [weak self, weak service] in
            guard let self = self else { return }
            do {
                try await service?.start()
                guard !Task.isCancelled, !self.isExplicitlyStopped else { return }
                await MainActor.run {
                    self.isRunning = true
                    self.status = .connected
                }
            } catch {
                guard !Task.isCancelled, !self.isExplicitlyStopped else { return }
                await MainActor.run {
                    self.isRunning = false
                    self.status = .error(error.localizedDescription)
                    self.scheduleReconnect()
                }
                LogManager.shared.add(level: .error, proxyTag: nil, message: "启动失败: \(error.localizedDescription)")
            }
        }
    }

    private func startExternalProcess(binaryPath: String, configURL: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binaryPath)
        p.arguments = ["-c", configURL.path]

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            self?.parseRealFrpLog(line)
        }

        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isRunning = false
                self.status = .disconnected
                LogManager.shared.add(level: .warn, proxyTag: nil, message: "FRP 进程已退出 (code: \(proc.terminationStatus))")
                self.scheduleReconnect()
            }
        }

        do {
            try p.run()
            self.process = p
            self.stdoutPipe = pipe
            self.isRunning = true
            self.status = .connecting
            LogManager.shared.add(level: .info, proxyTag: nil, message: "FRP 外部客户端已启动 (PID: \(p.processIdentifier))")
        } catch {
            self.status = .error(error.localizedDescription)
            LogManager.shared.add(level: .error, proxyTag: nil, message: "启动失败: \(error.localizedDescription)")
        }
    }

    private func stopInternal() {
        serviceTask?.cancel()
        serviceTask = nil

        let svc = clientService
        clientService = nil

        Task {
            await svc?.detachCallbacks()
            await svc?.stop()
        }

        if let p = process, p.isRunning {
            p.terminate()
        }
        process = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil

        for (id, _) in proxyStatuses {
            proxyStatuses[id] = .stopped
        }

        isRunning = false
        status = .disconnected
    }

    public func stop() {
        isExplicitlyStopped = true
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil

        stopInternal()
        LogManager.shared.add(level: .info, proxyTag: nil, message: "已断开连接")
    }

    private func scheduleReconnect() {
        guard !isExplicitlyStopped, let server = lastServer, let settings = lastSettings, settings.autoReconnect else {
            return
        }
        reconnectWorkItem?.cancel()
        let interval = max(1, settings.retryIntervalSeconds)
        LogManager.shared.add(level: .warn, proxyTag: nil, message: "\(interval) 秒后尝试自动重新连接...")

        let item = DispatchWorkItem { [weak self] in
            guard let self = self, !self.isExplicitlyStopped else { return }
            self.start(server: server, proxies: self.lastProxies, settings: settings)
        }
        reconnectWorkItem = item
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
        guard proxy.isEnabled else { return .stopped }
        guard isRunning && status != .disconnected else { return .stopped }
        return proxyStatuses[proxy.id] ?? .stopped
    }

    public var failedProxies: [FRPProxy] {
        AppState.shared.currentProxies.filter { proxy in
            proxy.isEnabled && (proxyStatuses[proxy.id]?.isFailed == true)
        }
    }

    public var failedProxiesCount: Int {
        failedProxies.count
    }

    public var hasProxyErrors: Bool {
        !failedProxies.isEmpty
    }

    private func updateProxyStatus(proxyName: String, runtimeStatus: FRPProxyRuntimeStatus) {
        let matchedId = proxyNameToId[proxyName] ?? lastProxies.first(where: {
            tagForProxyName($0.name) == proxyName || $0.name == proxyName || $0.name.lowercased() == proxyName.lowercased()
        })?.id ?? AppState.shared.currentProxies.first(where: {
            tagForProxyName($0.name) == proxyName || $0.name == proxyName || $0.name.lowercased() == proxyName.lowercased()
        })?.id

        if let id = matchedId {
            proxyStatuses[id] = runtimeStatus

            if case .failed(let err) = runtimeStatus {
                let displayName = AppState.shared.proxies.first(where: { $0.id == id })?.name ?? proxyName
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

    private func parseRealFrpLog(_ output: String) {
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

            for proxy in AppState.shared.currentProxies {
                let tag = tagForProxyName(proxy.name)
                if displayMessage.contains("[\(tag)]") || displayMessage.contains("[\(proxy.name)]") {
                    proxyTag = tag
                    break
                }
            }

            if let matchedProxy = AppState.shared.currentProxies.first(where: {
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
                        self.updateProxyStatus(proxyName: matchedProxy.name, runtimeStatus: .failed(error: errMsg))
                    } else if displayMessage.contains("start proxy success") {
                        self.updateProxyStatus(proxyName: matchedProxy.name, runtimeStatus: .running(remoteAddr: nil))
                    }
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if displayMessage.contains("login to server success") || displayMessage.contains("start proxy success") {
                    self.status = .connected
                } else if displayMessage.contains("login to the server failed") || displayMessage.contains("connect to server error") {
                    self.status = .error("连接失败")
                }
            }

            LogManager.shared.add(level: level, proxyTag: proxyTag, message: displayMessage)
        }
    }
}
