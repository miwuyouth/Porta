import Foundation

public struct AdminRequest: Sendable {
    public var method: String
    public var path: String
    public var queryParams: [String: String]
    public var headers: [String: String]
    public var body: Data?

    public init(
        method: String,
        path: String,
        queryParams: [String: String] = [:],
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.method = method.uppercased()
        self.path = path
        self.queryParams = queryParams
        self.headers = headers
        self.body = body
    }
}

public struct AdminResponse: Sendable {
    public var statusCode: Int
    public var headers: [String: String]
    public var body: Data

    public init(statusCode: Int, headers: [String: String] = ["Content-Type": "application/json"], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    public var bodyString: String {
        String(data: body, encoding: .utf8) ?? ""
    }
}

public final class FRPClientController: @unchecked Sendable {
    private let configManager: ConfigManager
    private let authToken: String?
    private let runID: String
    private let version: String

    public init(
        configManager: ConfigManager,
        authToken: String? = nil,
        runID: String = "run-admin-test",
        version: String = "0.61.0"
    ) {
        self.configManager = configManager
        self.authToken = authToken
        self.runID = runID
        self.version = version
    }

    public func handle(request: AdminRequest) async -> AdminResponse {
        // 1. Auth check
        if let token = authToken, !token.isEmpty {
            let authHeader = request.headers["Authorization"] ?? request.headers["authorization"] ?? ""
            if authHeader != "Bearer \(token)" && authHeader != token {
                let errBody = try? JSONEncoder().encode(["error": "unauthorized"])
                return AdminResponse(statusCode: 401, body: errBody ?? Data())
            }
        }

        // 2. Dispatch routes
        let path = request.path

        if path == "/api/status" {
            guard request.method == "GET" else {
                return AdminResponse(statusCode: 405)
            }
            let proxies = configManager.getAllProxies()
            let statusDict: [String: Any] = [
                "version": version,
                "run_id": runID,
                "proxies_count": proxies.count,
                "status": "online"
            ]
            let data = try? JSONSerialization.data(withJSONObject: statusDict, options: [])
            return AdminResponse(statusCode: 200, body: data ?? Data())
        }

        if path == "/api/config" {
            if request.method == "GET" {
                let current = configManager.currentConfig
                let data = try? JSONEncoder().encode(current)
                return AdminResponse(statusCode: 200, body: data ?? Data())
            } else if request.method == "PUT" {
                guard let body = request.body,
                      let newConfig = try? JSONDecoder().decode(FRPClientConfig.self, from: body) else {
                    let errBody = try? JSONEncoder().encode(["error": "invalid json payload"])
                    return AdminResponse(statusCode: 400, body: errBody ?? Data())
                }
                do {
                    _ = try configManager.reload(newConfig: newConfig)
                    let okBody = try? JSONEncoder().encode(["status": "config updated"])
                    return AdminResponse(statusCode: 200, body: okBody ?? Data())
                } catch {
                    let errBody = try? JSONEncoder().encode(["error": error.localizedDescription])
                    return AdminResponse(statusCode: 400, body: errBody ?? Data())
                }
            } else {
                return AdminResponse(statusCode: 405)
            }
        }

        if path == "/api/reload" {
            guard request.method == "POST" else {
                return AdminResponse(statusCode: 405)
            }
            let okBody = try? JSONEncoder().encode(["status": "reloaded"])
            return AdminResponse(statusCode: 200, body: okBody ?? Data())
        }

        if path == "/api/proxy" {
            guard request.method == "GET" else {
                return AdminResponse(statusCode: 405)
            }
            var proxies = configManager.getAllProxies()
            if let typeFilter = request.queryParams["type"] {
                proxies = proxies.filter { $0.type.rawValue.lowercased() == typeFilter.lowercased() }
            }
            let data = try? JSONEncoder().encode(proxies)
            return AdminResponse(statusCode: 200, body: data ?? Data())
        }

        if path.hasPrefix("/api/proxy/") {
            let proxyName = String(path.dropFirst("/api/proxy/".count))
            guard request.method == "GET" else {
                return AdminResponse(statusCode: 405)
            }
            guard let proxy = configManager.getProxy(name: proxyName) else {
                let errBody = try? JSONEncoder().encode(["error": "proxy not found"])
                return AdminResponse(statusCode: 404, body: errBody ?? Data())
            }
            let data = try? JSONEncoder().encode(proxy)
            return AdminResponse(statusCode: 200, body: data ?? Data())
        }

        if path == "/api/visitor" {
            guard request.method == "GET" else {
                return AdminResponse(statusCode: 405)
            }
            let okBody = try? JSONEncoder().encode(["visitors": [String]()])
            return AdminResponse(statusCode: 200, body: okBody ?? Data())
        }

        return AdminResponse(statusCode: 404, body: Data("{\"error\": \"not found\"}".utf8))
    }
}
