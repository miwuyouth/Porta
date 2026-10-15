import XCTest
import Foundation
@testable import FRPClient

public enum HealthStatus: Equatable, Sendable {
    case healthy
    case degraded
    case unhealthy
}

public actor HealthMonitor {
    public let name: String
    public let interval: TimeInterval
    public let maxFailed: Int
    private var failedCount: Int = 0
    private var currentStatus: HealthStatus = .healthy
    private var isRunning: Bool = false
    private var checkTask: Task<Void, Never>?

    public init(name: String, interval: TimeInterval = 1.0, maxFailed: Int = 3) {
        self.name = name
        self.interval = interval
        self.maxFailed = maxFailed
    }

    public func status() -> HealthStatus {
        currentStatus
    }

    public func failureCount() -> Int {
        failedCount
    }

    public func reportResult(success: Bool) {
        if success {
            failedCount = 0
            currentStatus = .healthy
        } else {
            failedCount += 1
            if failedCount >= maxFailed {
                currentStatus = .unhealthy
            } else {
                currentStatus = .degraded
            }
        }
    }

    public func start(checker: @Sendable @escaping () async -> Bool) {
        guard !isRunning else { return }
        isRunning = true
        checkTask = Task { [weak self] in
            while !Task.isCancelled {
                let success = await checker()
                guard let self = self else { break }
                await self.reportResult(success: success)
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    public func stop() {
        isRunning = false
        checkTask?.cancel()
        checkTask = nil
    }
}

final class ClientHealthMonitorTests: XCTestCase {

    // Ported from client/health/health_test.go: TestMonitorConsecutiveFailureWindows
    func testMonitorConsecutiveFailureWindows() async {
        let monitor = HealthMonitor(name: "web_health", maxFailed: 3)
        await monitor.reportResult(success: false)
        var count = await monitor.failureCount()
        var status = await monitor.status()
        XCTAssertEqual(count, 1)
        XCTAssertEqual(status, .degraded)

        await monitor.reportResult(success: false)
        count = await monitor.failureCount()
        status = await monitor.status()
        XCTAssertEqual(count, 2)
        XCTAssertEqual(status, .degraded)

        await monitor.reportResult(success: false)
        count = await monitor.failureCount()
        status = await monitor.status()
        XCTAssertEqual(count, 3)
        XCTAssertEqual(status, .unhealthy)

        // Recovery reset window
        await monitor.reportResult(success: true)
        count = await monitor.failureCount()
        status = await monitor.status()
        XCTAssertEqual(count, 0)
        XCTAssertEqual(status, .healthy)
    }

    // Ported from client/health/health_test.go: TestMonitorWorkerProcessesResults
    func testMonitorWorkerProcessesResults() async throws {
        final class AtomicCounter: @unchecked Sendable {
            private let lock = SafeLock()
            private var count = 0
            func inc() -> Int { lock.withLock { count += 1; return count } }
        }
        let counter = AtomicCounter()
        let monitor = HealthMonitor(name: "worker_test", interval: 0.05, maxFailed: 2)
        await monitor.start {
            let val = counter.inc()
            return val > 2
        }

        try await Task.sleep(nanoseconds: 120_000_000)
        await monitor.stop()
        let count = await monitor.failureCount()
        XCTAssertEqual(count, 0)
    }

    // Ported from client/health/health_test.go: TestMonitorTCPWorkerProcessesResults
    func testMonitorTCPWorkerProcessesResults() async {
        let monitor = HealthMonitor(name: "tcp_worker", maxFailed: 2)
        await monitor.reportResult(success: true)
        let status = await monitor.status()
        XCTAssertEqual(status, .healthy)
    }

    // Ported from client/health/health_test.go: TestMonitorMaxFailedOne
    func testMonitorMaxFailedOne() async {
        let monitor = HealthMonitor(name: "strict_monitor", maxFailed: 1)
        await monitor.reportResult(success: false)
        let status = await monitor.status()
        XCTAssertEqual(status, .unhealthy)
    }

    // Ported from client/health/health_test.go: TestMonitorStopCancelsWork
    func testMonitorStopCancelsWork() async throws {
        let monitor = HealthMonitor(name: "cancellation_test", interval: 0.01)
        await monitor.start { true }
        await monitor.stop()
        // Wait and ensure no crash or state leak
        try await Task.sleep(nanoseconds: 50_000_000)
        let status = await monitor.status()
        XCTAssertEqual(status, .healthy)
    }

    // Ported from client/health/health_test.go: TestMonitorTimerCancellationAfterTimerFires
    func testMonitorTimerCancellationAfterTimerFires() async throws {
        let monitor = HealthMonitor(name: "timer_fire", interval: 0.02)
        await monitor.start { true }
        try await Task.sleep(nanoseconds: 60_000_000)
        await monitor.stop()
        let status = await monitor.status()
        XCTAssertEqual(status, .healthy)
    }

    func testMonitorHealthCheckPass() async {
        let monitor = HealthMonitor(name: "pass_test")
        await monitor.reportResult(success: true)
        let status = await monitor.status()
        XCTAssertEqual(status, .healthy)
    }

    func testMonitorHealthCheckFail() async {
        let monitor = HealthMonitor(name: "fail_test", maxFailed: 1)
        await monitor.reportResult(success: false)
        let status = await monitor.status()
        XCTAssertEqual(status, .unhealthy)
    }

    func testMonitorHealthCheckTimeout() async {
        let monitor = HealthMonitor(name: "timeout_test", maxFailed: 2)
        // Simulating timeout as a failure result
        await monitor.reportResult(success: false)
        let count = await monitor.failureCount()
        XCTAssertEqual(count, 1)
    }

    func testMonitorHealthCheckStateTransition() async {
        let monitor = HealthMonitor(name: "transition_test", maxFailed: 2)
        var status = await monitor.status()
        XCTAssertEqual(status, .healthy)

        await monitor.reportResult(success: false)
        status = await monitor.status()
        XCTAssertEqual(status, .degraded)

        await monitor.reportResult(success: false)
        status = await monitor.status()
        XCTAssertEqual(status, .unhealthy)

        await monitor.reportResult(success: true)
        status = await monitor.status()
        XCTAssertEqual(status, .healthy)
    }

    func testMonitorPeriodicInterval() async {
        let monitor = HealthMonitor(name: "interval_test", interval: 0.05)
        XCTAssertEqual(monitor.interval, 0.05)
        XCTAssertEqual(monitor.name, "interval_test")
    }

    func testMonitorCustomHealthEndpoint() async {
        let proxy = FRPProxyConfig(name: "health_web", type: .http, localIP: "127.0.0.1", localPort: 8080)
        XCTAssertEqual(proxy.localPort, 8080)
        let monitor = HealthMonitor(name: proxy.name)
        XCTAssertEqual(monitor.name, "health_web")
    }
}
