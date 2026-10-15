import Foundation

public enum FRPClientError: Error, CustomStringConvertible, LocalizedError, Sendable {
    case loginFailed(String)
    case proxyRegisterFailed(name: String, error: String)
    case connectionLost
    case stopped

    public var description: String {
        switch self {
        case .loginFailed(let msg):
            return "登录 FRP 服务器失败: \(msg)"
        case .proxyRegisterFailed(let name, let error):
            return "代理 [\(name)] 注册失败: \(error)"
        case .connectionLost:
            return "控制连接已断开"
        case .stopped:
            return "FRP 客户端服务已停止"
        }
    }

    public var errorDescription: String? {
        description
    }
}

public enum FRPClientLogLevel: String, Sendable {
    case debug
    case info
    case warn
    case error
}

public actor FRPClientService {
    public let config: FRPClientConfig
    public var onLog: (@Sendable (FRPClientLogLevel, String?, String) -> Void)?
    public var onStatusChange: (@Sendable (Bool, String?) -> Void)?

    private var connector: (any Connector)?
    private var ctlConn: (any AsyncConnection)?
    private var runID: String = ""
    private var isRunning: Bool = false
    private var proxyHandlers: [String: any ProxyHandler] = [:]

    public var isRunningStatus: Bool { isRunning }
    public var currentRunID: String { runID }

    private var customConnector: (any Connector)?
    private var heartbeatTask: Task<Void, Never>?
    private var messageLoopTask: Task<Void, Never>?
    private var pendingProxyRegistrations: [String: CheckedContinuation<FRPNewProxyRespMessage, any Error>] = [:]

    public init(
        config: FRPClientConfig,
        connector: (any Connector)? = nil,
        proxyHandlers: [String: any ProxyHandler]? = nil,
        onLog: (@Sendable (FRPClientLogLevel, String?, String) -> Void)? = nil,
        onStatusChange: (@Sendable (Bool, String?) -> Void)? = nil
    ) {
        self.config = config
        self.customConnector = connector
        self.onLog = onLog
        self.onStatusChange = onStatusChange
        if let handlers = proxyHandlers {
            self.proxyHandlers = handlers
        } else {
            for proxyCfg in config.proxies {
                self.proxyHandlers[proxyCfg.name] = DefaultProxyHandler(config: proxyCfg, authToken: config.auth.token)
            }
        }
    }

    private func log(_ message: String, level: FRPClientLogLevel = .info, tag: String? = nil) {
        print("[FRP Client] \(message)")
        onLog?(level, tag, message)
    }

    /// Starts the FRP Client service.
    public func start() async throws {
        guard !isRunning else { return }
        isRunning = true

        do {
            log("正在连接服务器 \(config.serverAddr):\(config.serverPort)...")

            let conn = self.customConnector ?? DefaultConnector(config: config)
            self.connector = conn
            try await conn.open()

            let controlConnection = try await conn.connect()
            self.ctlConn = controlConnection

            // 1. Perform Login
            try await performLogin(on: controlConnection)

            // 2. Start receiving messages from control connection
            startMessageLoop(on: controlConnection)

            // 3. Register Proxies
            try await registerProxies(on: controlConnection)

            // 4. Start Heartbeat if needed
            startHeartbeat(on: controlConnection)

            log("服务器连接成功")
            onStatusChange?(true, nil)
        } catch {
            stop()
            throw error
        }
    }

    /// Stops the FRP Client service.
    public func stop() {
        guard isRunning else { return }
        isRunning = false

        for (_, cont) in pendingProxyRegistrations {
            cont.resume(throwing: FRPClientError.stopped)
        }
        pendingProxyRegistrations.removeAll()

        heartbeatTask?.cancel()
        heartbeatTask = nil

        messageLoopTask?.cancel()
        messageLoopTask = nil

        ctlConn?.close()
        ctlConn = nil

        connector?.close()
        connector = nil

        runID = ""

        log("FRP 服务已停止")
        onStatusChange?(false, nil)
    }

    /// Detaches callbacks so that asynchronous teardown does not affect new service instances.
    public func detachCallbacks() {
        self.onLog = nil
        self.onStatusChange = nil
    }

    private func performLogin(on connection: any AsyncConnection) async throws {
        let timestamp = Int64(Date().timeIntervalSince1970)
        let privilegeKey = FRPAuth.getAuthKey(token: config.auth.token, timestamp: timestamp)

        let loginMsg = FRPLoginMessage(
            version: "0.61.0",
            hostname: Host.current().localizedName ?? "swift-client",
            os: "darwin",
            arch: "arm64",
            user: config.user,
            privilegeKey: privilegeKey,
            timestamp: timestamp,
            runID: "",
            poolCount: config.transport.poolCount
        )

        try await connection.writeMessage(loginMsg)

        let resp = try await connection.readMessage()
        guard let loginResp = resp as? FRPLoginRespMessage else {
            throw FRPClientError.loginFailed("Expected LoginResp, got \(type(of: resp))")
        }

        if let error = loginResp.error, !error.isEmpty {
            log("登录服务器失败: \(error)", level: .error)
            throw FRPClientError.loginFailed(error)
        }

        self.runID = loginResp.runID ?? ""
        log("登录成功，分配 runID: \(self.runID)")
    }

    private func registerProxies(on connection: any AsyncConnection) async throws {
        for (name, handler) in proxyHandlers {
            let newProxyMsg = handler.makeNewProxyMessage()
            log("正在注册代理 [\(name)]，类型: \(handler.config.type)...", tag: name)

            let resp: FRPNewProxyRespMessage = try await withCheckedThrowingContinuation { continuation in
                self.pendingProxyRegistrations[name] = continuation
                Task {
                    do {
                        try await connection.writeMessage(newProxyMsg)
                    } catch {
                        self.failPendingRegistration(name: name, error: error)
                    }
                }
            }

            if let error = resp.error, !error.isEmpty {
                log("代理 [\(name)] 注册失败: \(error)", level: .error, tag: name)
                if config.loginFailExit {
                    throw FRPClientError.proxyRegisterFailed(name: name, error: error)
                }
            } else {
                let remoteAddr = resp.remoteAddr ?? "established"
                log("代理 [\(name)] 注册成功 -> \(remoteAddr)", level: .info, tag: name)
            }
        }
    }

    private func failPendingRegistration(name: String, error: Error) {
        if let cont = pendingProxyRegistrations.removeValue(forKey: name) {
            cont.resume(throwing: error)
        }
    }

    private func startHeartbeat(on connection: any AsyncConnection) {
        let interval = config.transport.heartbeatInterval
        guard interval > 0 else { return }

        let token = config.auth.token
        let additionalScopes = config.auth.additionalScopes ?? (token.isEmpty ? [] : ["HeartBeats", "NewWorkConns"])

        heartbeatTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))

                let timestamp = Int64(Date().timeIntervalSince1970)
                var ping = FRPPingMessage(timestamp: timestamp)
                if !token.isEmpty && additionalScopes.contains("HeartBeats") {
                    ping.privilegeKey = FRPAuth.getAuthKey(token: token, timestamp: timestamp)
                }

                do {
                    try await connection.writeMessage(ping)
                    log("心跳正常")
                } catch {
                    log("心跳发送失败: \(error)", level: .warn)
                    break
                }
            }
        }
    }

    private func startMessageLoop(on connection: any AsyncConnection) {
        messageLoopTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let msg = try await connection.readMessage()
                    guard let self = self else { break }
                    await self.handleIncomingMessage(msg)
                } catch {
                    guard let self = self, await self.isRunning else { break }
                    await self.log("控制连接断开: \(error)", level: .warn)
                    break
                }
            }
            await self?.stop()
        }
    }

    private func handleIncomingMessage(_ message: any FRPMessage) async {
        switch message {
        case is FRPReqWorkConnMessage:
            Task {
                await self.dispatchNewWorkConnection()
            }
        case let newProxyResp as FRPNewProxyRespMessage:
            handleNewProxyResp(newProxyResp)
        case let pong as FRPPongMessage:
            if let error = pong.error, !error.isEmpty {
                log("收到 Pong 错误: \(error)", level: .warn)
            }
        default:
            break
        }
    }

    private func handleNewProxyResp(_ resp: FRPNewProxyRespMessage) {
        guard let name = resp.proxyName else {
            if pendingProxyRegistrations.count == 1, let key = pendingProxyRegistrations.keys.first, let cont = pendingProxyRegistrations.removeValue(forKey: key) {
                cont.resume(returning: resp)
            }
            return
        }
        if let cont = pendingProxyRegistrations.removeValue(forKey: name) {
            cont.resume(returning: resp)
            return
        }
        for (key, cont) in pendingProxyRegistrations {
            if name.hasSuffix(key) || key.hasSuffix(name) {
                pendingProxyRegistrations.removeValue(forKey: key)
                cont.resume(returning: resp)
                return
            }
        }
    }

    private func dispatchNewWorkConnection() async {
        guard let connector = self.connector else { return }

        do {
            let workConn = try await connector.connect()

            var newWorkConnMsg = FRPNewWorkConnMessage(runID: self.runID)
            let token = config.auth.token
            let additionalScopes = config.auth.additionalScopes ?? (token.isEmpty ? [] : ["HeartBeats", "NewWorkConns"])
            if !token.isEmpty && additionalScopes.contains("NewWorkConns") {
                let timestamp = Int64(Date().timeIntervalSince1970)
                newWorkConnMsg.timestamp = timestamp
                newWorkConnMsg.privilegeKey = FRPAuth.getAuthKey(token: token, timestamp: timestamp)
            }

            try await workConn.writeMessage(newWorkConnMsg)

            let resp = try await workConn.readMessage()
            guard let startMsg = resp as? FRPStartWorkConnMessage else {
                log("建立工作连接异常，收到未知响应: \(type(of: resp))", level: .warn)
                workConn.close()
                return
            }

            if let error = startMsg.error, !error.isEmpty {
                log("StartWorkConn 错误: \(error)", level: .error)
                workConn.close()
                return
            }

            let requestedName = startMsg.proxyName
            var resolvedHandler: (any ProxyHandler)? = proxyHandlers[requestedName]

            if resolvedHandler == nil && !config.user.isEmpty && requestedName.hasPrefix("\(config.user).") {
                let stripped = String(requestedName.dropFirst(config.user.count + 1))
                resolvedHandler = proxyHandlers[stripped]
            }

            if resolvedHandler == nil {
                for (key, handler) in proxyHandlers {
                    if requestedName.hasSuffix(key) || key.hasSuffix(requestedName) || key.caseInsensitiveCompare(requestedName) == .orderedSame {
                        resolvedHandler = handler
                        break
                    }
                }
            }

            guard let handler = resolvedHandler else {
                log("未找到代理处理器: \(startMsg.proxyName)", level: .warn, tag: startMsg.proxyName)
                workConn.close()
                return
            }

            log("已建立工作连接 [\(startMsg.proxyName)]", level: .info, tag: startMsg.proxyName)
            Task {
                await handler.handleWorkConn(workConn, startMsg: startMsg)
            }
        } catch {
            log("建立工作连接失败: \(error)", level: .error)
        }
    }
}
