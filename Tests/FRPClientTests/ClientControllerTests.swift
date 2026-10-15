import XCTest
@testable import FRPClient

final class ClientControllerTests: XCTestCase {

    func testControllerGetStatusSuccess() async {
        let p = FRPProxyConfig(name: "web", localPort: 80)
        let manager = ConfigManager(config: FRPClientConfig(proxies: [p]))
        let controller = FRPClientController(configManager: manager, runID: "run-test-id", version: "0.61.0")

        let req = AdminRequest(method: "GET", path: "/api/status")
        let resp = await controller.handle(request: req)

        XCTAssertEqual(resp.statusCode, 200)
        XCTAssertTrue(resp.bodyString.contains("run-test-id"))
        XCTAssertTrue(resp.bodyString.contains("0.61.0"))
    }

    func testControllerGetConfig() async throws {
        let manager = ConfigManager(config: FRPClientConfig(serverAddr: "test.controller.com"))
        let controller = FRPClientController(configManager: manager)

        let req = AdminRequest(method: "GET", path: "/api/config")
        let resp = await controller.handle(request: req)

        XCTAssertEqual(resp.statusCode, 200)
        let config = try JSONDecoder().decode(FRPClientConfig.self, from: resp.body)
        XCTAssertEqual(config.serverAddr, "test.controller.com")
    }

    func testControllerPutConfigValid() async throws {
        let manager = ConfigManager(config: FRPClientConfig(serverAddr: "old.com"))
        let controller = FRPClientController(configManager: manager)

        let newCfg = FRPClientConfig(serverAddr: "new.com", auth: FRPAuthConfig(token: "tok"))
        let bodyData = try JSONEncoder().encode(newCfg)
        let req = AdminRequest(method: "PUT", path: "/api/config", body: bodyData)

        let resp = await controller.handle(request: req)
        XCTAssertEqual(resp.statusCode, 200)
        XCTAssertEqual(manager.currentConfig.serverAddr, "new.com")
    }

    func testControllerPutConfigInvalidJSON() async {
        let manager = ConfigManager(config: FRPClientConfig())
        let controller = FRPClientController(configManager: manager)

        let req = AdminRequest(method: "PUT", path: "/api/config", body: Data("corrupt-json".utf8))
        let resp = await controller.handle(request: req)
        XCTAssertEqual(resp.statusCode, 400)
    }

    func testControllerReloadTriggered() async {
        let manager = ConfigManager(config: FRPClientConfig())
        let controller = FRPClientController(configManager: manager)

        let req = AdminRequest(method: "POST", path: "/api/reload")
        let resp = await controller.handle(request: req)
        XCTAssertEqual(resp.statusCode, 200)
        XCTAssertTrue(resp.bodyString.contains("reloaded"))
    }

    func testControllerGetProxiesFilterByType() async throws {
        let p1 = FRPProxyConfig(name: "tcp1", type: .tcp, localPort: 80)
        let p2 = FRPProxyConfig(name: "http1", type: .http, localPort: 8080, customDomains: ["a.com"])
        let manager = ConfigManager(config: FRPClientConfig(proxies: [p1, p2]))
        let controller = FRPClientController(configManager: manager)

        let req = AdminRequest(method: "GET", path: "/api/proxy", queryParams: ["type": "http"])
        let resp = await controller.handle(request: req)
        XCTAssertEqual(resp.statusCode, 200)

        let proxies = try JSONDecoder().decode([FRPProxyConfig].self, from: resp.body)
        XCTAssertEqual(proxies.count, 1)
        XCTAssertEqual(proxies[0].name, "http1")
    }

    func testControllerGetProxyByNameFound() async throws {
        let p = FRPProxyConfig(name: "target-proxy", type: .tcp, localPort: 22)
        let manager = ConfigManager(config: FRPClientConfig(proxies: [p]))
        let controller = FRPClientController(configManager: manager)

        let req = AdminRequest(method: "GET", path: "/api/proxy/target-proxy")
        let resp = await controller.handle(request: req)
        XCTAssertEqual(resp.statusCode, 200)

        let proxy = try JSONDecoder().decode(FRPProxyConfig.self, from: resp.body)
        XCTAssertEqual(proxy.name, "target-proxy")
        XCTAssertEqual(proxy.localPort, 22)
    }

    func testControllerGetProxyByNameNotFound() async {
        let manager = ConfigManager(config: FRPClientConfig())
        let controller = FRPClientController(configManager: manager)

        let req = AdminRequest(method: "GET", path: "/api/proxy/unknown")
        let resp = await controller.handle(request: req)
        XCTAssertEqual(resp.statusCode, 404)
    }

    func testControllerNotFoundEndpoint() async {
        let manager = ConfigManager(config: FRPClientConfig())
        let controller = FRPClientController(configManager: manager)

        let req = AdminRequest(method: "GET", path: "/api/nonexistent")
        let resp = await controller.handle(request: req)
        XCTAssertEqual(resp.statusCode, 404)
    }

    func testControllerAuthSuccessAndFailure() async {
        let manager = ConfigManager(config: FRPClientConfig())
        let controller = FRPClientController(configManager: manager, authToken: "admin-secret-key")

        // 1. Without auth header -> 401
        let reqNoAuth = AdminRequest(method: "GET", path: "/api/status")
        let resp401 = await controller.handle(request: reqNoAuth)
        XCTAssertEqual(resp401.statusCode, 401)

        // 2. With wrong auth header -> 401
        let reqWrong = AdminRequest(method: "GET", path: "/api/status", headers: ["Authorization": "Bearer wrong-key"])
        let respWrong = await controller.handle(request: reqWrong)
        XCTAssertEqual(respWrong.statusCode, 401)

        // 3. With correct auth header -> 200
        let reqOk = AdminRequest(method: "GET", path: "/api/status", headers: ["Authorization": "Bearer admin-secret-key"])
        let respOk = await controller.handle(request: reqOk)
        XCTAssertEqual(respOk.statusCode, 200)
    }
}
