import XCTest
@testable import FRPClient

final class ClientConfigManagerTests: XCTestCase {

    func testConfigManagerInitialLoad() {
        let p1 = FRPProxyConfig(name: "ssh", localPort: 22)
        let config = FRPClientConfig(proxies: [p1])
        let manager = ConfigManager(config: config)

        XCTAssertEqual(manager.getAllProxies().count, 1)
        XCTAssertEqual(manager.getProxy(name: "ssh")?.localPort, 22)
    }

    func testConfigManagerAddProxy() throws {
        let manager = ConfigManager(config: FRPClientConfig())
        let newProxy = FRPProxyConfig(name: "web", type: .tcp, localPort: 80, remotePort: 8080)

        try manager.addProxy(newProxy)
        XCTAssertEqual(manager.getAllProxies().count, 1)
        XCTAssertEqual(manager.getProxy(name: "web")?.remotePort, 8080)
    }

    func testConfigManagerAddDuplicateProxyFails() throws {
        let p = FRPProxyConfig(name: "dup", localPort: 80)
        let manager = ConfigManager(config: FRPClientConfig(proxies: [p]))

        XCTAssertThrowsError(try manager.addProxy(p)) { error in
            XCTAssertEqual(error as? ConfigManager.ManagerError, .proxyAlreadyExists("dup"))
        }
    }

    func testConfigManagerUpdateProxy() throws {
        let p = FRPProxyConfig(name: "web", localPort: 80)
        let manager = ConfigManager(config: FRPClientConfig(proxies: [p]))

        let updated = FRPProxyConfig(name: "web", localPort: 8080)
        try manager.updateProxy(updated)

        XCTAssertEqual(manager.getProxy(name: "web")?.localPort, 8080)
    }

    func testConfigManagerRemoveProxy() throws {
        let p = FRPProxyConfig(name: "temp", localPort: 80)
        let manager = ConfigManager(config: FRPClientConfig(proxies: [p]))

        try manager.removeProxy(name: "temp")
        XCTAssertNil(manager.getProxy(name: "temp"))
        XCTAssertEqual(manager.getAllProxies().count, 0)
    }

    func testConfigManagerRemoveNonexistentProxyFails() {
        let manager = ConfigManager(config: FRPClientConfig())
        XCTAssertThrowsError(try manager.removeProxy(name: "ghost")) { error in
            XCTAssertEqual(error as? ConfigManager.ManagerError, .proxyNotFound("ghost"))
        }
    }

    func testConfigManagerCalculateReloadDiff() {
        let p1 = FRPProxyConfig(name: "keep", localPort: 80)
        let p2 = FRPProxyConfig(name: "modify", localPort: 80)
        let p3 = FRPProxyConfig(name: "delete", localPort: 80)
        let manager = ConfigManager(config: FRPClientConfig(proxies: [p1, p2, p3]))

        let p2Modified = FRPProxyConfig(name: "modify", localPort: 90) // modified port
        let p4 = FRPProxyConfig(name: "added", localPort: 100)
        let newConfig = FRPClientConfig(proxies: [p1, p2Modified, p4])

        let diff = manager.calculateDiff(newConfig: newConfig)
        XCTAssertEqual(diff.added, ["added"])
        XCTAssertEqual(diff.removed, ["delete"])
        XCTAssertEqual(diff.modified, ["modify"])
    }

    func testConfigManagerCalculateDiffWithDuplicateProxiesDoesNotCrash() {
        let p1 = FRPProxyConfig(name: "dup", localPort: 80)
        let p2 = FRPProxyConfig(name: "dup", localPort: 90)
        let manager = ConfigManager(config: FRPClientConfig(proxies: []))

        let newConfig = FRPClientConfig(proxies: [p1, p2])
        let diff = manager.calculateDiff(newConfig: newConfig)
        XCTAssertEqual(diff.added, ["dup"])
    }

    func testConfigManagerVisitorAddAndLookup() throws {
        let manager = ConfigManager(config: FRPClientConfig())
        let visitor = VisitorConfig(
            name: "stcp-visitor",
            serverName: "stcp-server",
            secretKey: "secret",
            bindPort: 6000
        )
        try manager.addVisitor(visitor)

        let retrieved = manager.getVisitor(name: "stcp-visitor")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.serverName, "stcp-server")
        XCTAssertEqual(retrieved?.bindPort, 6000)
    }

    func testConfigManagerVisitorDependencyTracking() throws {
        let manager = ConfigManager(config: FRPClientConfig())
        let visitor = VisitorConfig(name: "v1", serverName: "target-service", secretKey: "key", bindPort: 7000)
        try manager.addVisitor(visitor)

        XCTAssertNotNil(manager.getVisitor(name: "v1"))
        try manager.removeVisitor(name: "v1")
        XCTAssertNil(manager.getVisitor(name: "v1"))
    }

    func testConfigManagerRollbackOnInvalidUpdate() {
        let validProxy = FRPProxyConfig(name: "valid", localPort: 80)
        let manager = ConfigManager(config: FRPClientConfig(serverAddr: "1.2.3.4", auth: FRPAuthConfig(token: "tok"), proxies: [validProxy]))

        let invalidConfig = FRPClientConfig(serverAddr: "   ") // empty serverAddr is invalid
        XCTAssertThrowsError(try manager.reload(newConfig: invalidConfig))

        // State preserved
        XCTAssertEqual(manager.currentConfig.serverAddr, "1.2.3.4")
        XCTAssertEqual(manager.getAllProxies().count, 1)
    }
}
