import XCTest
@testable import FRPClient

final class UtilVhostAndMetricsTests: XCTestCase {

    func testVhostRouterExactMatch() {
        let router = VhostRouter<String>()
        router.addRoute(domain: "test.example.com", handler: "handler1")
        XCTAssertEqual(router.getRoute(host: "test.example.com"), "handler1")
        XCTAssertEqual(router.getRoute(host: "TEST.example.com"), "handler1") // case-insensitive
    }

    func testVhostRouterWildcardMatch() {
        let router = VhostRouter<String>()
        router.addRoute(domain: "*.example.com", handler: "wildcard_handler")
        XCTAssertEqual(router.getRoute(host: "sub.example.com"), "wildcard_handler")
        XCTAssertEqual(router.getRoute(host: "api.dev.example.com"), "wildcard_handler")
        XCTAssertNil(router.getRoute(host: "other.com"))
    }

    func testVhostRouterNoMatchReturnsNil() {
        let router = VhostRouter<String>()
        router.addRoute(domain: "api.frp.io", handler: "api_handler")
        XCTAssertNil(router.getRoute(host: "web.frp.io"))
    }

    func testVhostRouterPriorityExactOverWildcard() {
        let router = VhostRouter<String>()
        router.addRoute(domain: "*.example.com", handler: "wildcard")
        router.addRoute(domain: "special.example.com", handler: "exact")

        XCTAssertEqual(router.getRoute(host: "special.example.com"), "exact")
        XCTAssertEqual(router.getRoute(host: "normal.example.com"), "wildcard")
    }

    func testPathRouterPrefixMatch() {
        let router = PathRouter<String>()
        router.addRoute(prefix: "/static", handler: "static_files")
        router.addRoute(prefix: "/api", handler: "api_handler")

        XCTAssertEqual(router.match(path: "/static/css/style.css"), "static_files")
        XCTAssertEqual(router.match(path: "/api/users"), "api_handler")
        XCTAssertNil(router.match(path: "/home"))
    }

    func testPathRouterLongestPrefixMatch() {
        let router = PathRouter<String>()
        router.addRoute(prefix: "/api", handler: "general_api")
        router.addRoute(prefix: "/api/v2/users", handler: "v2_users")

        XCTAssertEqual(router.match(path: "/api/v2/users/123"), "v2_users")
        XCTAssertEqual(router.match(path: "/api/v1/users"), "general_api")
    }

    func testMetricsCollectorIncrementConnections() {
        let metrics = MetricsCollector()
        metrics.incrementConnection(proxyName: "web")
        metrics.incrementConnection(proxyName: "web")
        metrics.incrementConnection(proxyName: "ssh")

        let snap = metrics.snapshot()
        XCTAssertEqual(snap.connectionCounts["web"], 2)
        XCTAssertEqual(snap.connectionCounts["ssh"], 1)
        XCTAssertNil(snap.connectionCounts["unknown"])
    }

    func testMetricsCollectorTrackBandwidth() {
        let metrics = MetricsCollector()
        metrics.recordTraffic(proxyName: "web", bytesIn: 1024, bytesOut: 2048)
        metrics.recordTraffic(proxyName: "web", bytesIn: 512, bytesOut: 512)

        let snap = metrics.snapshot()
        XCTAssertEqual(snap.bytesIn["web"], 1536)
        XCTAssertEqual(snap.bytesOut["web"], 2560)
    }

    func testMetricsCollectorSnapshot() {
        let metrics = MetricsCollector()
        let emptySnap = metrics.snapshot()
        XCTAssertTrue(emptySnap.connectionCounts.isEmpty)
        XCTAssertTrue(emptySnap.bytesIn.isEmpty)
        XCTAssertTrue(emptySnap.bytesOut.isEmpty)
    }

    func testLogPrefixFormatterFormatting() {
        let str1 = LogPrefixFormatter.format(proxyName: "tcp-proxy", runID: "run-001", message: "Starting proxy")
        XCTAssertEqual(str1, "[run-001][tcp-proxy] Starting proxy")

        let str2 = LogPrefixFormatter.format(proxyName: "tcp-proxy", runID: nil, message: "Connected")
        XCTAssertEqual(str2, "[tcp-proxy] Connected")

        let str3 = LogPrefixFormatter.format(proxyName: nil, runID: nil, message: "Raw message")
        XCTAssertEqual(str3, "Raw message")
    }

    func testVhostRouterLongestWildcardMatchPriority() {
        let router = VhostRouter<String>()
        router.addRoute(domain: "*.example.com", handler: "general_wildcard")
        router.addRoute(domain: "*.api.example.com", handler: "specific_wildcard")

        XCTAssertEqual(router.getRoute(host: "v1.api.example.com"), "specific_wildcard")
        XCTAssertEqual(router.getRoute(host: "web.example.com"), "general_wildcard")
    }
}
