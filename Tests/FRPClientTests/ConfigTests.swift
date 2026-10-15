import XCTest
@testable import FRPClient

final class ConfigTests: XCTestCase {
    func testFullTOMLParsing() throws {
        let tomlString = """
        # Global server configuration
        serverAddr = "192.168.1.100" # Primary server
        serverPort = 7000
        user = "developer"
        loginFailExit = false

        [auth]
        method = "token"
        token = "secret_auth_token"
        additionalScopes = ["HeartBeats", "NewWorkConns"]

        [transport]
        tcpMux = true
        tls.enable = true
        tls.serverName = "frp.example.com"
        heartbeatInterval = 15
        heartbeatTimeout = 60
        dialServerTimeout = 5

        # Proxy 1: TCP
        [[proxies]]
        name = "ssh_proxy"
        type = "tcp"
        localIP = "127.0.0.1"
        localPort = 22
        remotePort = 6022
        transport.useEncryption = true
        transport.useCompression = true

        # Proxy 2: HTTP
        [[proxies]]
        name = "web_proxy"
        type = "http"
        localIP = "10.0.0.5"
        localPort = 8080
        customDomains = ["web.example.com", "app.example.com"]
        subdomain = "test"
        locations = ["/api", "/static"]
        hostHeaderRewrite = "dev.internal"
        httpUser = "admin"
        httpPassword = "password123"

        # Proxy 3: STCP
        [[proxies]]
        name = "secret_ssh"
        type = "stcp"
        localIP = "127.0.0.1"
        localPort = 2222
        secretKey = "stcp_super_secret"

        # Proxy 4: TCPMux
        [[proxies]]
        name = "mux_tunnel"
        type = "tcpmux"
        localIP = "127.0.0.1"
        localPort = 9000
        """

        let config = try SimpleTOMLParser.parse(content: tomlString)

        // Verify global config
        XCTAssertEqual(config.serverAddr, "192.168.1.100")
        XCTAssertEqual(config.serverPort, 7000)
        XCTAssertEqual(config.user, "developer")
        XCTAssertFalse(config.loginFailExit)

        // Verify auth
        XCTAssertEqual(config.auth.method, "token")
        XCTAssertEqual(config.auth.token, "secret_auth_token")
        XCTAssertEqual(config.auth.additionalScopes, ["HeartBeats", "NewWorkConns"])

        // Verify transport
        XCTAssertTrue(config.transport.tcpMux)
        XCTAssertTrue(config.transport.tlsEnable)
        XCTAssertEqual(config.transport.tlsServerName, "frp.example.com")
        XCTAssertEqual(config.transport.heartbeatInterval, 15)
        XCTAssertEqual(config.transport.heartbeatTimeout, 60)
        XCTAssertEqual(config.transport.dialServerTimeout, 5)

        // Verify proxies
        XCTAssertEqual(config.proxies.count, 4)

        // Proxy 1 (TCP)
        let p1 = config.proxies[0]
        XCTAssertEqual(p1.name, "ssh_proxy")
        XCTAssertEqual(p1.type, .tcp)
        XCTAssertEqual(p1.localIP, "127.0.0.1")
        XCTAssertEqual(p1.localPort, 22)
        XCTAssertEqual(p1.remotePort, 6022)
        XCTAssertTrue(p1.useEncryption)
        XCTAssertTrue(p1.useCompression)

        // Proxy 2 (HTTP)
        let p2 = config.proxies[1]
        XCTAssertEqual(p2.name, "web_proxy")
        XCTAssertEqual(p2.type, .http)
        XCTAssertEqual(p2.localIP, "10.0.0.5")
        XCTAssertEqual(p2.localPort, 8080)
        XCTAssertEqual(p2.customDomains, ["web.example.com", "app.example.com"])
        XCTAssertEqual(p2.subdomain, "test")
        XCTAssertEqual(p2.locations, ["/api", "/static"])
        XCTAssertEqual(p2.hostHeaderRewrite, "dev.internal")
        XCTAssertEqual(p2.httpUser, "admin")
        XCTAssertEqual(p2.httpPassword, "password123")

        // Proxy 3 (STCP)
        let p3 = config.proxies[2]
        XCTAssertEqual(p3.name, "secret_ssh")
        XCTAssertEqual(p3.type, .stcp)
        XCTAssertEqual(p3.secretKey, "stcp_super_secret")

        // Proxy 4 (TCPMux)
        let p4 = config.proxies[3]
        XCTAssertEqual(p4.name, "mux_tunnel")
        XCTAssertEqual(p4.type, .tcpmux)
    }

    func testMinimalConfigDefaults() throws {
        let minimal = """
        serverAddr = "custom.host"
        serverPort = 8000
        """

        let config = try SimpleTOMLParser.parse(content: minimal)
        XCTAssertEqual(config.serverAddr, "custom.host")
        XCTAssertEqual(config.serverPort, 8000)
        XCTAssertEqual(config.user, "")
        XCTAssertEqual(config.auth.token, "")
        XCTAssertTrue(config.transport.tcpMux)
        XCTAssertFalse(config.transport.tlsEnable)
        XCTAssertEqual(config.transport.heartbeatInterval, 30)
        XCTAssertEqual(config.transport.heartbeatTimeout, 90)
        XCTAssertEqual(config.transport.dialServerTimeout, 10)
        XCTAssertTrue(config.loginFailExit)
        XCTAssertTrue(config.proxies.isEmpty)
    }

    func testCommentAndWhitespaceHandling() throws {
        let content = """
        ; Semicolon comment
        # Hash comment
           serverAddr   =   "10.0.0.1"    # Trailing comment
           serverPort   =   7001          ; Trailing comment
        """

        let config = try SimpleTOMLParser.parse(content: content)
        XCTAssertEqual(config.serverAddr, "10.0.0.1")
        XCTAssertEqual(config.serverPort, 7001)
    }
}
