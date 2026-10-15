import Foundation

public enum SimpleTOMLParser {
    public static func parse(content: String) throws -> FRPClientConfig {
        var serverAddr = "127.0.0.1"
        var serverPort = 7000
        var user = ""
        var authToken = ""
        var authMethod = "token"
        var tcpMux = true
        var tlsEnable = false
        var tlsServerName: String?
        var loginFailExit = true
        var authAdditionalScopes: [String]?
        var heartbeatInterval: TimeInterval = 30
        var heartbeatTimeout: TimeInterval = 90
        var dialServerTimeout: TimeInterval = 10
        var poolCount = 0
        var proxies: [FRPProxyConfig] = []

        var currentProxy: [String: Any]?
        var currentSection = ""

        let lines = content.components(separatedBy: .newlines)

        func commitCurrentProxy() {
            guard let dict = currentProxy, let name = dict["name"] as? String else { return }
            let typeStr = (dict["type"] as? String)?.lowercased() ?? "tcp"
            let type = FRPProxyType(rawValue: typeStr) ?? .tcp
            let localIP = (dict["localIP"] as? String) ?? (dict["local_ip"] as? String) ?? "127.0.0.1"
            let localPort = (dict["localPort"] as? Int) ?? (dict["local_port"] as? Int) ?? 0
            let remotePort = (dict["remotePort"] as? Int) ?? (dict["remote_port"] as? Int)
            let customDomains = (dict["customDomains"] as? [String]) ?? (dict["custom_domains"] as? [String])
            let subdomain = (dict["subdomain"] as? String)
            let locations = (dict["locations"] as? [String])
            let hostHeaderRewrite = (dict["hostHeaderRewrite"] as? String) ?? (dict["host_header_rewrite"] as? String)
            let httpUser = (dict["httpUser"] as? String) ?? (dict["http_user"] as? String)
            let httpPassword = (dict["httpPassword"] as? String) ?? (dict["http_password"] as? String) ?? (dict["httpPwd"] as? String) ?? (dict["http_pwd"] as? String)
            let secretKey = (dict["secretKey"] as? String) ?? (dict["secret_key"] as? String)
            let useEncryption = (dict["transport.useEncryption"] as? Bool) ?? (dict["useEncryption"] as? Bool) ?? false
            let useCompression = (dict["transport.useCompression"] as? Bool) ?? (dict["useCompression"] as? Bool) ?? false

            let proxy = FRPProxyConfig(
                name: name,
                type: type,
                localIP: localIP,
                localPort: localPort,
                remotePort: remotePort,
                customDomains: customDomains,
                subdomain: subdomain,
                locations: locations,
                hostHeaderRewrite: hostHeaderRewrite,
                httpUser: httpUser,
                httpPassword: httpPassword,
                secretKey: secretKey,
                useEncryption: useEncryption,
                useCompression: useCompression
            )
            proxies.append(proxy)
            currentProxy = nil
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") {
                continue
            }

            if line.hasPrefix("[[") && line.hasSuffix("]]") {
                commitCurrentProxy()
                let sectionName = String(line.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
                currentSection = sectionName
                if sectionName == "proxies" {
                    currentProxy = [:]
                }
                continue
            }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                commitCurrentProxy()
                currentSection = String(line.dropFirst(1).dropLast(1)).trimmingCharacters(in: .whitespaces)
                continue
            }

            // Key = Value
            guard let equalIndex = line.firstIndex(of: "=") else {
                continue
            }

            let key = String(line[..<equalIndex]).trimmingCharacters(in: .whitespaces)
            let valStr = String(line[line.index(after: equalIndex)...]).trimmingCharacters(in: .whitespaces)
            let val = parseValue(valStr)

            let fullKey: String
            if !currentSection.isEmpty && currentSection != "proxies" {
                fullKey = "\(currentSection).\(key)"
            } else {
                fullKey = key
            }

            if currentSection == "proxies" {
                currentProxy?[key] = val
                continue
            }

            switch fullKey.lowercased() {
            case "serveraddr", "server_addr":
                if let s = val as? String { serverAddr = s }
            case "serverport", "server_port":
                if let i = val as? Int { serverPort = i }
            case "user":
                if let s = val as? String { user = s }
            case "auth.token", "token":
                if let s = val as? String { authToken = s }
            case "auth.method", "method":
                if let s = val as? String { authMethod = s }
            case "auth.additionalscopes", "auth.additional_scopes", "additionalscopes", "additional_scopes":
                if let arr = val as? [String] { authAdditionalScopes = arr }
            case "transport.tcpmux", "tcpmux":
                if let b = val as? Bool { tcpMux = b }
            case "transport.tls.enable", "tls.enable", "tls_enable":
                if let b = val as? Bool { tlsEnable = b }
            case "transport.tls.servername", "tls.servername", "tls_server_name":
                if let s = val as? String { tlsServerName = s }
            case "transport.heartbeatinterval", "transport.heartbeat_interval", "heartbeatinterval", "heartbeat_interval":
                if let i = val as? Int { heartbeatInterval = TimeInterval(i) }
            case "transport.heartbeattimeout", "transport.heartbeat_timeout", "heartbeattimeout", "heartbeat_timeout":
                if let i = val as? Int { heartbeatTimeout = TimeInterval(i) }
            case "transport.dialservertimeout", "transport.dial_server_timeout", "dialservertimeout", "dial_server_timeout":
                if let i = val as? Int { dialServerTimeout = TimeInterval(i) }
            case "transport.poolcount", "transport.pool_count", "poolcount", "pool_count":
                if let i = val as? Int { poolCount = i }
            case "loginfailexit", "login_fail_exit":
                if let b = val as? Bool { loginFailExit = b }
            default:
                break
            }
        }

        commitCurrentProxy()

        let authConfig = FRPAuthConfig(
            method: authMethod,
            token: authToken,
            additionalScopes: authAdditionalScopes
        )
        let transportConfig = FRPTransportConfig(
            tcpMux: tcpMux,
            tlsEnable: tlsEnable,
            tlsServerName: tlsServerName,
            heartbeatInterval: heartbeatInterval,
            heartbeatTimeout: heartbeatTimeout,
            dialServerTimeout: dialServerTimeout,
            poolCount: poolCount
        )

        return FRPClientConfig(
            serverAddr: serverAddr,
            serverPort: serverPort,
            user: user,
            auth: authConfig,
            transport: transportConfig,
            loginFailExit: loginFailExit,
            proxies: proxies
        )
    }

    private static func parseValue(_ raw: String) -> Any {
        var str = raw.trimmingCharacters(in: .whitespaces)

        // String enclosed in quotes
        if str.hasPrefix("\"") {
            if let closingIdx = str.dropFirst().firstIndex(of: "\"") {
                return String(str[str.index(after: str.startIndex)..<closingIdx])
            }
        }
        if str.hasPrefix("'") {
            if let closingIdx = str.dropFirst().firstIndex(of: "'") {
                return String(str[str.index(after: str.startIndex)..<closingIdx])
            }
        }

        // Strip trailing comments (# or ;)
        if let commentIndex = str.firstIndex(where: { $0 == "#" || $0 == ";" }) {
            str = String(str[..<commentIndex]).trimmingCharacters(in: .whitespaces)
        }

        // Boolean
        if str.lowercased() == "true" { return true }
        if str.lowercased() == "false" { return false }

        // Integer
        if let intVal = Int(str) { return intVal }

        // Array of strings
        if str.hasPrefix("[") && str.hasSuffix("]") {
            let inner = String(str.dropFirst().dropLast())
            let items = inner.components(separatedBy: ",")
            return items.map { item -> String in
                var s = item.trimmingCharacters(in: .whitespaces)
                if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
                    s = String(s.dropFirst().dropLast())
                }
                return s
            }.filter { !$0.isEmpty }
        }

        return str
    }
}
