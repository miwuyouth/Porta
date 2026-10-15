import XCTest
@testable import FRPClient

final class PluginAndNatholeTests: XCTestCase {

    func testHTTPProxyPluginHandler() {
        let plugin = HTTPProxyPlugin(httpUser: "admin", httpPassword: "secret-password")
        XCTAssertEqual(plugin.name, "http_proxy")
        XCTAssertEqual(plugin.httpUser, "admin")
        XCTAssertEqual(plugin.httpPassword, "secret-password")
    }

    func testStaticFilePluginPathResolution() {
        let plugin = StaticFilePlugin(localPath: "/var/www/html", stripPrefix: "/static")
        XCTAssertEqual(plugin.name, "static_file")

        let resolved = plugin.resolvePath("/static/js/app.js")
        XCTAssertEqual(resolved, "/var/www/html/js/app.js")

        // Directory traversal attack attempt
        let traversal = plugin.resolvePath("/static/../../etc/passwd")
        XCTAssertNil(traversal)

        // Sibling directory traversal attempt (/var/www vs /var/www-secret)
        let siblingTraversal = plugin.resolvePath("/static/../html-secret/passwords.txt")
        XCTAssertNil(siblingTraversal)
    }

    func testUnixDomainSocketPluginConfig() {
        let plugin = UnixDomainSocketPlugin(unixPath: "/tmp/docker.sock")
        XCTAssertEqual(plugin.name, "unix_domain_socket")
        XCTAssertEqual(plugin.unixPath, "/tmp/docker.sock")
    }

    func testPluginManagerRegistrationAndLookup() {
        let manager = PluginManager()
        let httpPlugin = HTTPProxyPlugin()
        let unixPlugin = UnixDomainSocketPlugin(unixPath: "/tmp/app.sock")

        manager.registerPlugin(httpPlugin)
        manager.registerPlugin(unixPlugin)

        XCTAssertNotNil(manager.getPlugin(name: "http_proxy"))
        XCTAssertNotNil(manager.getPlugin(name: "unix_domain_socket"))
        XCTAssertNil(manager.getPlugin(name: "unknown_plugin"))
    }

    func testNatHoleSessionIDGeneration() {
        let session = NatHoleSession()
        XCTAssertFalse(session.sid.isEmpty)

        let sessionCustom = NatHoleSession(sid: "custom-sid-123")
        XCTAssertEqual(sessionCustom.sid, "custom-sid-123")
    }

    func testNatHoleCandidateAddressExchange() {
        let session = NatHoleSession()
        XCTAssertEqual(session.state, .initial)

        session.updateCandidates(
            visitor: ["1.1.1.1:10001", "192.168.1.10:10001"],
            client: ["2.2.2.2:20002"]
        )

        let candidates = session.getCandidates()
        XCTAssertEqual(candidates.visitor.count, 2)
        XCTAssertEqual(candidates.client.count, 1)
        XCTAssertEqual(session.state, .ready)
    }

    func testNatHoleStateTransition() {
        let session = NatHoleSession()
        XCTAssertEqual(session.state, .initial)

        session.transition(to: .discovering)
        XCTAssertEqual(session.state, .discovering)

        session.transition(to: .closed)
        XCTAssertEqual(session.state, .closed)
    }

    func testProxyNamingCanonicalFormat() {
        let canonicalWithUser = ProxyNaming.canonicalName(user: "alice", proxyName: "ssh")
        XCTAssertEqual(canonicalWithUser, "alice.ssh")

        let canonicalNoUser = ProxyNaming.canonicalName(user: "", proxyName: "web")
        XCTAssertEqual(canonicalNoUser, "web")
    }

    func testProxyNamingParseUserAndProxy() {
        let (user1, proxy1) = ProxyNaming.parseCanonicalName("alice.ssh")
        XCTAssertEqual(user1, "alice")
        XCTAssertEqual(proxy1, "ssh")

        let (user2, proxy2) = ProxyNaming.parseCanonicalName("plain_proxy")
        XCTAssertNil(user2)
        XCTAssertEqual(proxy2, "plain_proxy")
    }
}
