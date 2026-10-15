import XCTest
@testable import FRPClient

final class ConfigSourceTests: XCTestCase {

    func testMemoryConfigSourceLoad() throws {
        let original = FRPClientConfig(serverAddr: "192.168.1.1", serverPort: 7000)
        let memSource = MemoryConfigSource(config: original)
        let loaded = try memSource.load()
        XCTAssertEqual(loaded.serverAddr, "192.168.1.1")
        XCTAssertEqual(loaded.serverPort, 7000)
    }

    func testFileConfigSourceLoad() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_frpc_\(UUID().uuidString).toml")
        let tomlContent = """
        serverAddr = "10.0.0.5"
        serverPort = 7001
        """
        try tomlContent.write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileSource = FileConfigSource(filePath: fileURL.path)
        let config = try fileSource.load()
        XCTAssertEqual(config.serverAddr, "10.0.0.5")
        XCTAssertEqual(config.serverPort, 7001)
    }

    func testFileConfigSourceNotFound() {
        let fileSource = FileConfigSource(filePath: "/nonexistent/path/frpc.toml")
        XCTAssertThrowsError(try fileSource.load())
    }

    func testAggregatorSourceCombinesMultipleSources() throws {
        let p1 = FRPProxyConfig(name: "ssh", localPort: 22)
        let p2 = FRPProxyConfig(name: "web", localPort: 80)

        let s1 = MemoryConfigSource(config: FRPClientConfig(serverAddr: "1.1.1.1", proxies: [p1]))
        let s2 = MemoryConfigSource(config: FRPClientConfig(serverAddr: "ignored", proxies: [p2]))

        let agg = AggregatorConfigSource(sources: [s1, s2])
        let combined = try agg.load()

        XCTAssertEqual(combined.serverAddr, "1.1.1.1")
        XCTAssertEqual(combined.proxies.count, 2)
        XCTAssertEqual(combined.proxies.map { $0.name }, ["ssh", "web"])
    }

    func testAggregatorSourceOrderPrecedence() throws {
        let s1 = MemoryConfigSource(config: FRPClientConfig(serverAddr: "primary.host", serverPort: 7000))
        let s2 = MemoryConfigSource(config: FRPClientConfig(serverAddr: "secondary.host", serverPort: 8000))

        let agg = AggregatorConfigSource(sources: [s1, s2])
        let config = try agg.load()
        XCTAssertEqual(config.serverAddr, "primary.host")
        XCTAssertEqual(config.serverPort, 7000)
    }

    func testAggregatorSourceDuplicateProxyDetection() {
        let p1 = FRPProxyConfig(name: "dup", localPort: 80)
        let p2 = FRPProxyConfig(name: "dup", localPort: 81)

        let s1 = MemoryConfigSource(config: FRPClientConfig(proxies: [p1]))
        let s2 = MemoryConfigSource(config: FRPClientConfig(proxies: [p2]))

        let agg = AggregatorConfigSource(sources: [s1, s2])
        XCTAssertThrowsError(try agg.load()) { error in
            XCTAssertEqual(error as? ValidationError, .duplicateProxyName("dup"))
        }
    }

    @MainActor
    func testConfigSourceWatchChangeNotification() async {
        let watcher = ConfigWatcher()
        let exp = expectation(description: "Watcher notified")

        _ = watcher.watch { config in
            XCTAssertEqual(config.serverAddr, "new.host")
            exp.fulfill()
        }

        watcher.notifyChange(FRPClientConfig(serverAddr: "new.host"))
        await fulfillment(of: [exp], timeout: 1.0)
    }

    func testConfigSourceUnwatch() {
        let watcher = ConfigWatcher()
        let id = watcher.watch { _ in }
        XCTAssertEqual(watcher.activeWatcherCount, 1)

        watcher.unwatch(id: id)
        XCTAssertEqual(watcher.activeWatcherCount, 0)
    }

    func testConfigSourceMultipleUnwatchOrder() {
        let watcher = ConfigWatcher()
        let id1 = watcher.watch { _ in }
        let id2 = watcher.watch { _ in }
        let id3 = watcher.watch { _ in }
        XCTAssertEqual(watcher.activeWatcherCount, 3)

        // Unwatch middle first
        watcher.unwatch(id: id2)
        XCTAssertEqual(watcher.activeWatcherCount, 2)

        // Unwatch first
        watcher.unwatch(id: id1)
        XCTAssertEqual(watcher.activeWatcherCount, 1)

        // Unwatch last
        watcher.unwatch(id: id3)
        XCTAssertEqual(watcher.activeWatcherCount, 0)
    }

    func testConfigSourceReloadData() throws {
        let mem = MemoryConfigSource(config: FRPClientConfig(serverAddr: "v1.host"))
        XCTAssertEqual(try mem.load().serverAddr, "v1.host")

        mem.update(config: FRPClientConfig(serverAddr: "v2.host"))
        XCTAssertEqual(try mem.load().serverAddr, "v2.host")
    }

    func testConfigSourceFormatAutoDetection() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let jsonURL = tempDir.appendingPathComponent("test_\(UUID().uuidString).json")
        let jsonContent = """
        {
            "serverAddr": "json.host",
            "serverPort": 7000,
            "user": "tester",
            "auth": { "method": "token", "token": "tok" },
            "transport": { "protocolType": "tcp", "tcpMux": true, "tlsEnable": false, "heartbeatInterval": 30, "heartbeatTimeout": 90, "dialServerTimeout": 10 },
            "loginFailExit": true,
            "proxies": []
        }
        """
        try jsonContent.write(to: jsonURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: jsonURL) }

        let source = FileConfigSource(filePath: jsonURL.path)
        let loaded = try source.load()
        XCTAssertEqual(loaded.serverAddr, "json.host")
        XCTAssertEqual(loaded.user, "tester")
    }

    func testConfigSourceAtomicSwap() {
        let mem = MemoryConfigSource(config: FRPClientConfig(serverAddr: "init"))
        mem.update(config: FRPClientConfig(serverAddr: "swapped"))
        XCTAssertEqual(try? mem.load().serverAddr, "swapped")
    }

    func testConfigSourceThreadSafety() {
        let mem = MemoryConfigSource(config: FRPClientConfig(serverAddr: "start"))
        let queue = DispatchQueue(label: "test.threadsafety", attributes: .concurrent)
        let group = DispatchGroup()

        for i in 0..<50 {
            group.enter()
            queue.async {
                mem.update(config: FRPClientConfig(serverAddr: "addr-\(i)"))
                _ = try? mem.load()
                group.leave()
            }
        }

        group.wait()
        XCTAssertNotNil(try? mem.load())
    }
}
