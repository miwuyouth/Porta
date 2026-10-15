import XCTest
@testable import FRPClient

final class ConfigTypesAndDecodeTests: XCTestCase {

    func testDecodeMinimalTOML() throws {
        let toml = """
        serverAddr = "1.2.3.4"
        serverPort = 7000
        """
        let config = try SimpleTOMLParser.parse(content: toml)
        XCTAssertEqual(config.serverAddr, "1.2.3.4")
        XCTAssertEqual(config.serverPort, 7000)
        XCTAssertEqual(config.proxies.count, 0)
    }

    func testDecodeFullTOMLWithMultipleProxies() throws {
        let toml = """
        serverAddr = "10.0.0.1"
        serverPort = 7000
        auth.token = "my-secret-token"

        [[proxies]]
        name = "p1"
        type = "tcp"
        localPort = 22
        remotePort = 6000

        [[proxies]]
        name = "p2"
        type = "http"
        localPort = 8080
        customDomains = ["a.example.com"]
        """
        let config = try SimpleTOMLParser.parse(content: toml)
        XCTAssertEqual(config.serverAddr, "10.0.0.1")
        XCTAssertEqual(config.auth.token, "my-secret-token")
        XCTAssertEqual(config.proxies.count, 2)
        XCTAssertEqual(config.proxies[0].name, "p1")
        XCTAssertEqual(config.proxies[0].remotePort, 6000)
        XCTAssertEqual(config.proxies[1].name, "p2")
        XCTAssertEqual(config.proxies[1].customDomains, ["a.example.com"])
    }

    func testDecodeJSONFormatConfig() throws {
        let jsonStr = """
        {
            "serverAddr": "192.168.1.100",
            "serverPort": 7000,
            "user": "alice",
            "auth": { "method": "token", "token": "tok123" },
            "transport": { "protocolType": "tcp", "tcpMux": true, "tlsEnable": false, "heartbeatInterval": 30, "heartbeatTimeout": 90, "dialServerTimeout": 10 },
            "loginFailExit": true,
            "proxies": [
                {
                    "name": "ssh",
                    "type": "tcp",
                    "localIP": "127.0.0.1",
                    "localPort": 22,
                    "remotePort": 2222,
                    "useEncryption": false,
                    "useCompression": false
                }
            ]
        }
        """
        let data = jsonStr.data(using: .utf8)!
        let config = try JSONDecoder().decode(FRPClientConfig.self, from: data)
        XCTAssertEqual(config.serverAddr, "192.168.1.100")
        XCTAssertEqual(config.user, "alice")
        XCTAssertEqual(config.proxies.count, 1)
        XCTAssertEqual(config.proxies[0].name, "ssh")
        XCTAssertEqual(config.proxies[0].remotePort, 2222)
    }

    func testDecodeDefaultValuesApplied() throws {
        let toml = "serverAddr = \"4.3.2.1\""
        let config = try SimpleTOMLParser.parse(content: toml)
        XCTAssertEqual(config.serverPort, 7000)
        XCTAssertEqual(config.auth.method, "token")
        XCTAssertEqual(config.transport.heartbeatInterval, 30)
        XCTAssertEqual(config.transport.heartbeatTimeout, 90)
        XCTAssertEqual(config.transport.dialServerTimeout, 10)
        XCTAssertTrue(config.loginFailExit)
    }

    func testDecodeInvalidTOMLSyntax() throws {
        let toml = """
        # Only comments and blank lines
        # No actual settings
        """
        let config = try SimpleTOMLParser.parse(content: toml)
        XCTAssertEqual(config.serverAddr, "127.0.0.1")
        XCTAssertEqual(config.serverPort, 7000)
    }

    func testCloneClientConfigIndependence() {
        var c1 = FRPClientConfig(serverAddr: "1.1.1.1", serverPort: 7000)
        c1.proxies = [FRPProxyConfig(name: "p1", localPort: 80)]
        var c2 = c1
        c2.serverAddr = "2.2.2.2"
        c2.proxies.append(FRPProxyConfig(name: "p2", localPort: 81))

        XCTAssertEqual(c1.serverAddr, "1.1.1.1")
        XCTAssertEqual(c1.proxies.count, 1)
        XCTAssertEqual(c2.serverAddr, "2.2.2.2")
        XCTAssertEqual(c2.proxies.count, 2)
    }

    func testCloneProxyConfigDeepCopy() {
        let p1 = FRPProxyConfig(name: "http1", type: .http, localPort: 80, customDomains: ["dom1.com"])
        var p2 = p1
        p2.customDomains?.append("dom2.com")
        p2.name = "http2"

        XCTAssertEqual(p1.name, "http1")
        XCTAssertEqual(p1.customDomains, ["dom1.com"])
        XCTAssertEqual(p2.name, "http2")
        XCTAssertEqual(p2.customDomains, ["dom1.com", "dom2.com"])
    }

    func testPortRangeParserSinglePort() throws {
        let ports = try PortRangeParser.parse("8080")
        XCTAssertEqual(ports, [8080])
    }

    func testPortRangeParserMultipleRanges() throws {
        let ports = try PortRangeParser.parse("80, 443, 6000-6003")
        XCTAssertEqual(ports, [80, 443, 6000, 6001, 6002, 6003])
    }

    func testPortRangeParserOverlappingRangesDeduplication() throws {
        let ports = try PortRangeParser.parse("6000-6003, 6002-6005, 6001")
        XCTAssertEqual(ports, [6000, 6001, 6002, 6003, 6004, 6005])
    }

    func testPortRangeParserInvalidFormat() {
        XCTAssertThrowsError(try PortRangeParser.parse("80,abc,90")) { error in
            XCTAssertEqual(error as? PortRangeParser.ParseError, .invalidFormat("abc"))
        }
        XCTAssertThrowsError(try PortRangeParser.parse("6005-6000")) { error in
            XCTAssertEqual(error as? PortRangeParser.ParseError, .invalidRange(start: 6005, end: 6000))
        }
    }

    func testPortRangeParserOutOfRangePort() {
        XCTAssertThrowsError(try PortRangeParser.parse("70000")) { error in
            XCTAssertEqual(error as? PortRangeParser.ParseError, .portOutOfRange(70000))
        }
        XCTAssertThrowsError(try PortRangeParser.parse("0")) { error in
            XCTAssertEqual(error as? PortRangeParser.ParseError, .portOutOfRange(0))
        }
    }

    func testDurationParserSeconds() throws {
        let d = try DurationParser.parse("45s")
        XCTAssertEqual(d, 45.0)
    }

    func testDurationParserMinutes() throws {
        let d = try DurationParser.parse("5m")
        XCTAssertEqual(d, 300.0)
    }

    func testDurationParserMilliseconds() throws {
        let d = try DurationParser.parse("500ms")
        XCTAssertEqual(d, 0.5)
    }

    func testDurationParserInvalidFormat() {
        XCTAssertThrowsError(try DurationParser.parse("not-a-duration"))
        XCTAssertThrowsError(try DurationParser.parse("30x"))
    }

    func testBandwidthBytesParserKB() throws {
        let b = try BandwidthParser.parseBytes("10KB")
        XCTAssertEqual(b, 10 * 1024)
    }

    func testBandwidthBytesParserMB() throws {
        let b = try BandwidthParser.parseBytes("5MB")
        XCTAssertEqual(b, 5 * 1024 * 1024)
    }

    func testBandwidthBytesParserGB() throws {
        let b = try BandwidthParser.parseBytes("2GB")
        XCTAssertEqual(b, 2 * 1024 * 1024 * 1024)
    }

    func testBandwidthBytesParserInvalidString() {
        XCTAssertThrowsError(try BandwidthParser.parseBytes("10TB"))
        XCTAssertThrowsError(try BandwidthParser.parseBytes("-5MB"))
        XCTAssertThrowsError(try BandwidthParser.parseBytes("invalid"))
    }

    func testValueSourceEnvExpansionSimple() {
        let template = "serverAddr = \"{{ .Envs.FRP_SERVER_HOST }}\""
        let env = ["FRP_SERVER_HOST": "frp.myhost.com"]
        let expanded = EnvExpander.expand(template, env: env)
        XCTAssertEqual(expanded, "serverAddr = \"frp.myhost.com\"")
    }

    func testValueSourceEnvExpansionDefaultFallback() {
        let template = "serverPort = {{ .Envs.FRP_PORT | default \"7000\" }}"
        let expanded = EnvExpander.expand(template, env: [:])
        XCTAssertEqual(expanded, "serverPort = 7000")
    }

    func testValueSourceEnvExpansionMissingVar() {
        let template = "user = \"{{ .Envs.UNKNOWN_USER }}\""
        let expanded = EnvExpander.expand(template, env: [:])
        XCTAssertEqual(expanded, "user = \"{{ .Envs.UNKNOWN_USER }}\"")
    }

    func testProxyTypeFromStringCaseInsensitive() {
        XCTAssertEqual(FRPProxyType(rawValue: "tcp".lowercased()), .tcp)
        XCTAssertEqual(FRPProxyType(rawValue: "HTTP".lowercased()), .http)
        XCTAssertEqual(FRPProxyType(rawValue: "HTTPS".lowercased()), .https)
        XCTAssertEqual(FRPProxyType(rawValue: "stcp".lowercased()), .stcp)
        XCTAssertEqual(FRPProxyType(rawValue: "SUDP".lowercased()), .sudp)
        XCTAssertEqual(FRPProxyType(rawValue: "TCPmux".lowercased()), .tcpmux)
    }

    func testProxyHeaderMapDecoding() throws {
        let jsonStr = """
        {
            "name": "web-headers",
            "type": "http",
            "localIP": "127.0.0.1",
            "localPort": 80,
            "customDomains": ["api.example.com"],
            "hostHeaderRewrite": "localhost:80"
        }
        """
        let data = jsonStr.data(using: .utf8)!
        let proxy = try JSONDecoder().decode(FRPProxyConfig.self, from: data)
        XCTAssertEqual(proxy.hostHeaderRewrite, "localhost:80")
        XCTAssertEqual(proxy.customDomains, ["api.example.com"])
    }
}
