import XCTest
@testable import FRPClient

final class ConfigValidationTests: XCTestCase {

    func testValidateValidClientConfig() throws {
        let proxy = FRPProxyConfig(name: "web", type: .tcp, localIP: "127.0.0.1", localPort: 8080, remotePort: 18080)
        let config = FRPClientConfig(
            serverAddr: "1.2.3.4",
            serverPort: 7000,
            auth: FRPAuthConfig(method: "token", token: "secret-token"),
            transport: FRPTransportConfig(heartbeatInterval: 30, heartbeatTimeout: 90, dialServerTimeout: 10),
            proxies: [proxy]
        )
        XCTAssertNoThrow(try ConfigValidator.validateClientConfig(config))
    }

    func testValidateClientConfigEmptyServerAddr() {
        let config = FRPClientConfig(serverAddr: "   ")
        XCTAssertThrowsError(try ConfigValidator.validateClientConfig(config)) { error in
            XCTAssertEqual(error as? ValidationError, .emptyServerAddr)
        }
    }

    func testValidateClientConfigInvalidServerPort() {
        let configZero = FRPClientConfig(serverAddr: "127.0.0.1", serverPort: 0)
        XCTAssertThrowsError(try ConfigValidator.validateClientConfig(configZero)) { error in
            XCTAssertEqual(error as? ValidationError, .invalidServerPort(0))
        }

        let configTooHigh = FRPClientConfig(serverAddr: "127.0.0.1", serverPort: 70000)
        XCTAssertThrowsError(try ConfigValidator.validateClientConfig(configTooHigh)) { error in
            XCTAssertEqual(error as? ValidationError, .invalidServerPort(70000))
        }
    }

    func testValidateClientConfigInvalidHeartbeat() {
        var transport = FRPTransportConfig()
        transport.heartbeatInterval = 0
        let config = FRPClientConfig(serverAddr: "127.0.0.1", transport: transport)
        XCTAssertThrowsError(try ConfigValidator.validateClientConfig(config)) { error in
            XCTAssertEqual(error as? ValidationError, .invalidHeartbeatInterval(0))
        }

        var transport2 = FRPTransportConfig()
        transport2.heartbeatInterval = 30
        transport2.heartbeatTimeout = 20 // timeout <= interval is invalid
        let config2 = FRPClientConfig(serverAddr: "127.0.0.1", transport: transport2)
        XCTAssertThrowsError(try ConfigValidator.validateClientConfig(config2)) { error in
            XCTAssertEqual(error as? ValidationError, .invalidHeartbeatTimeout(timeout: 20, interval: 30))
        }
    }

    func testValidateClientConfigInvalidDialTimeout() {
        var transport = FRPTransportConfig()
        transport.dialServerTimeout = 0
        let config = FRPClientConfig(serverAddr: "127.0.0.1", transport: transport)
        XCTAssertThrowsError(try ConfigValidator.validateClientConfig(config)) { error in
            XCTAssertEqual(error as? ValidationError, .invalidDialServerTimeout(0))
        }
    }

    func testValidateAuthTokenEmptyWhenMethodToken() {
        let auth = FRPAuthConfig(method: "token", token: "  ")
        let config = FRPClientConfig(serverAddr: "127.0.0.1", auth: auth)
        XCTAssertThrowsError(try ConfigValidator.validateClientConfig(config)) { error in
            XCTAssertEqual(error as? ValidationError, .emptyAuthToken)
        }
    }

    func testValidateAuthOIDCSuccess() throws {
        XCTAssertNoThrow(try ConfigValidator.validateOIDC(clientID: "client-123", clientSecret: "sec-456"))
    }

    func testValidateAuthOIDCInvalidClientID() {
        XCTAssertThrowsError(try ConfigValidator.validateOIDC(clientID: "   ", clientSecret: "sec-456")) { error in
            XCTAssertEqual(error as? ValidationError, .invalidOIDCConfig("clientID cannot be empty"))
        }
    }

    func testValidateProxyNameValid() throws {
        XCTAssertNoThrow(try ConfigValidator.validateProxyName("valid-proxy_name.1"))
    }

    func testValidateProxyNameEmpty() {
        XCTAssertThrowsError(try ConfigValidator.validateProxyName("   "))
    }

    func testValidateProxyNameInvalidCharacters() {
        XCTAssertThrowsError(try ConfigValidator.validateProxyName("proxy/invalid"))
        XCTAssertThrowsError(try ConfigValidator.validateProxyName("proxy with spaces"))
        XCTAssertThrowsError(try ConfigValidator.validateProxyName("proxy@name"))
    }

    func testValidateProxyNameTooLong() {
        let longName = String(repeating: "a", count: 129)
        XCTAssertThrowsError(try ConfigValidator.validateProxyName(longName))
    }

    func testValidateTCPProxySuccess() throws {
        let proxy = FRPProxyConfig(name: "tcp-ok", type: .tcp, localIP: "127.0.0.1", localPort: 80, remotePort: 8080)
        XCTAssertNoThrow(try ConfigValidator.validateProxyConfig(proxy))
    }

    func testValidateTCPProxyInvalidLocalPort() {
        let proxy = FRPProxyConfig(name: "tcp-bad", type: .tcp, localIP: "127.0.0.1", localPort: 70000)
        XCTAssertThrowsError(try ConfigValidator.validateProxyConfig(proxy)) { error in
            XCTAssertEqual(error as? ValidationError, .invalidLocalPort(70000))
        }
    }

    func testValidateTCPProxyInvalidRemotePort() {
        let proxy = FRPProxyConfig(name: "tcp-bad", type: .tcp, localIP: "127.0.0.1", localPort: 80, remotePort: 90000)
        XCTAssertThrowsError(try ConfigValidator.validateProxyConfig(proxy)) { error in
            XCTAssertEqual(error as? ValidationError, .invalidRemotePort(90000))
        }
    }

    func testValidateTCPProxyInvalidLocalIP() {
        let proxy = FRPProxyConfig(name: "tcp-bad", type: .tcp, localIP: "127.0.0.1 bad", localPort: 80)
        XCTAssertThrowsError(try ConfigValidator.validateProxyConfig(proxy)) { error in
            XCTAssertEqual(error as? ValidationError, .invalidLocalIP("127.0.0.1 bad"))
        }
    }

    func testValidateUDPProxySuccess() throws {
        let proxy = FRPProxyConfig(name: "udp-ok", type: .udp, localIP: "127.0.0.1", localPort: 53, remotePort: 1053)
        XCTAssertNoThrow(try ConfigValidator.validateProxyConfig(proxy))
    }

    func testValidateUDPProxyMissingRemotePort() {
        let proxy = FRPProxyConfig(name: "udp-bad", type: .udp, localIP: "127.0.0.1", localPort: 53, remotePort: nil)
        XCTAssertThrowsError(try ConfigValidator.validateProxyConfig(proxy)) { error in
            XCTAssertEqual(error as? ValidationError, .invalidRemotePort(nil))
        }
    }

    func testValidateHTTPProxySuccessWithDomain() throws {
        let proxy = FRPProxyConfig(name: "http-ok", type: .http, localPort: 8080, customDomains: ["example.com", "*.test.org"])
        XCTAssertNoThrow(try ConfigValidator.validateProxyConfig(proxy))
    }

    func testValidateHTTPProxySuccessWithSubdomain() throws {
        let proxy = FRPProxyConfig(name: "http-sub", type: .http, localPort: 8080, subdomain: "my-service")
        XCTAssertNoThrow(try ConfigValidator.validateProxyConfig(proxy))
    }

    func testValidateHTTPProxyMissingDomainAndSubdomain() {
        let proxy = FRPProxyConfig(name: "http-empty", type: .http, localPort: 8080)
        XCTAssertThrowsError(try ConfigValidator.validateProxyConfig(proxy)) { error in
            XCTAssertEqual(error as? ValidationError, .missingHTTPDomainOrSubdomain(proxyName: "http-empty"))
        }
    }

    func testValidateHTTPProxyInvalidCustomDomain() {
        let proxy = FRPProxyConfig(name: "http-bad-domain", type: .http, localPort: 8080, customDomains: ["invalid domain/com"])
        XCTAssertThrowsError(try ConfigValidator.validateProxyConfig(proxy))
    }

    func testValidateHTTPProxyInvalidLocationPrefix() {
        let proxy = FRPProxyConfig(name: "http-bad-loc", type: .http, localPort: 8080, customDomains: ["a.com"], locations: ["static/files"])
        XCTAssertThrowsError(try ConfigValidator.validateProxyConfig(proxy)) { error in
            XCTAssertEqual(error as? ValidationError, .invalidLocationPrefix("static/files"))
        }
    }

    func testValidateHTTPSProxySuccess() throws {
        let proxy = FRPProxyConfig(name: "https-ok", type: .https, localPort: 8443, customDomains: ["secure.example.com"])
        XCTAssertNoThrow(try ConfigValidator.validateProxyConfig(proxy))
    }

    func testValidateHTTPSProxyMissingDomain() {
        let proxy = FRPProxyConfig(name: "https-missing", type: .https, localPort: 8443)
        XCTAssertThrowsError(try ConfigValidator.validateProxyConfig(proxy)) { error in
            XCTAssertEqual(error as? ValidationError, .missingHTTPDomainOrSubdomain(proxyName: "https-missing"))
        }
    }

    func testValidateSTCPProxySuccess() throws {
        let proxy = FRPProxyConfig(name: "stcp-ok", type: .stcp, localPort: 9000, secretKey: "abc12345")
        XCTAssertNoThrow(try ConfigValidator.validateProxyConfig(proxy))
    }

    func testValidateSTCPProxyMissingSecretKey() {
        let proxy = FRPProxyConfig(name: "stcp-nokey", type: .stcp, localPort: 9000, secretKey: "  ")
        XCTAssertThrowsError(try ConfigValidator.validateProxyConfig(proxy)) { error in
            XCTAssertEqual(error as? ValidationError, .missingSecretKey(proxyName: "stcp-nokey"))
        }
    }

    func testValidateSUDPProxySuccess() throws {
        let proxy = FRPProxyConfig(name: "sudp-ok", type: .sudp, localPort: 9001, secretKey: "sudp-secret")
        XCTAssertNoThrow(try ConfigValidator.validateProxyConfig(proxy))
    }

    func testValidateSUDPProxyMissingSecretKey() {
        let proxy = FRPProxyConfig(name: "sudp-bad", type: .sudp, localPort: 9001, secretKey: nil)
        XCTAssertThrowsError(try ConfigValidator.validateProxyConfig(proxy)) { error in
            XCTAssertEqual(error as? ValidationError, .missingSecretKey(proxyName: "sudp-bad"))
        }
    }

    func testValidateTCPMUXProxySuccess() throws {
        let proxy = FRPProxyConfig(name: "tcpmux-ok", type: .tcpmux, localPort: 8080, multiplexer: "httpconnect")
        XCTAssertNoThrow(try ConfigValidator.validateProxyConfig(proxy))
    }

    func testValidateTCPMUXProxyMissingMultiplexer() {
        let proxy = FRPProxyConfig(name: "tcpmux-nomux", type: .tcpmux, localPort: 8080, multiplexer: nil)
        XCTAssertThrowsError(try ConfigValidator.validateProxyConfig(proxy)) { error in
            XCTAssertEqual(error as? ValidationError, .missingMultiplexer(proxyName: "tcpmux-nomux"))
        }
    }

    func testValidateXTCPProxySuccess() throws {
        let proxy = FRPProxyConfig(name: "xtcp-ok", type: .xtcp, localPort: 1234, secretKey: "xtcp-sk")
        XCTAssertNoThrow(try ConfigValidator.validateProxyConfig(proxy))
    }

    func testValidateBandwidthLimitValidFormats() throws {
        XCTAssertNoThrow(try ConfigValidator.validateBandwidthLimit("10KB"))
        XCTAssertNoThrow(try ConfigValidator.validateBandwidthLimit("500MB"))
        XCTAssertNoThrow(try ConfigValidator.validateBandwidthLimit("2GB"))
        XCTAssertNoThrow(try ConfigValidator.validateBandwidthLimit("1024B"))
    }

    func testValidateBandwidthLimitInvalidFormats() {
        XCTAssertThrowsError(try ConfigValidator.validateBandwidthLimit("0MB"))
        XCTAssertThrowsError(try ConfigValidator.validateBandwidthLimit("-10MB"))
        XCTAssertThrowsError(try ConfigValidator.validateBandwidthLimit("10TB"))
        XCTAssertThrowsError(try ConfigValidator.validateBandwidthLimit("abc"))
    }

    func testValidateDuplicateProxyNamesFails() {
        let p1 = FRPProxyConfig(name: "same_name", type: .tcp, localPort: 80, remotePort: 8080)
        let p2 = FRPProxyConfig(name: "same_name", type: .tcp, localPort: 81, remotePort: 8081)
        let config = FRPClientConfig(
            serverAddr: "127.0.0.1",
            auth: FRPAuthConfig(method: "token", token: "tok"),
            proxies: [p1, p2]
        )
        XCTAssertThrowsError(try ConfigValidator.validateClientConfig(config)) { error in
            XCTAssertEqual(error as? ValidationError, .duplicateProxyName("same_name"))
        }
    }
}
