import XCTest
@testable import FRPClient

final class UtilNetAndBackoffTests: XCTestCase {

    func testSplitHostPortIPv4() throws {
        let (host, port) = try NetUtil.splitHostPort("127.0.0.1:8080")
        XCTAssertEqual(host, "127.0.0.1")
        XCTAssertEqual(port, 8080)
    }

    func testSplitHostPortIPv6() throws {
        let (host, port) = try NetUtil.splitHostPort("[::1]:9000")
        XCTAssertEqual(host, "::1")
        XCTAssertEqual(port, 9000)
    }

    func testSplitHostPortDefaultPort() throws {
        let (host, port) = try NetUtil.splitHostPort("example.com", defaultPort: 7000)
        XCTAssertEqual(host, "example.com")
        XCTAssertEqual(port, 7000)

        let (host6, port6) = try NetUtil.splitHostPort("[2001:db8::1]", defaultPort: 7000)
        XCTAssertEqual(host6, "2001:db8::1")
        XCTAssertEqual(port6, 7000)
    }

    func testSplitHostPortInvalid() {
        XCTAssertThrowsError(try NetUtil.splitHostPort(""))
        XCTAssertThrowsError(try NetUtil.splitHostPort("1.2.3.4:not-a-port"))
        XCTAssertThrowsError(try NetUtil.splitHostPort("1.2.3.4:70000"))
        XCTAssertThrowsError(try NetUtil.splitHostPort("2001:db8::1")) // raw IPv6 without brackets
    }

    func testIsLoopbackAddress() {
        XCTAssertTrue(NetUtil.isLoopback("127.0.0.1"))
        XCTAssertTrue(NetUtil.isLoopback("127.1.2.3"))
        XCTAssertTrue(NetUtil.isLoopback("::1"))
        XCTAssertTrue(NetUtil.isLoopback("localhost"))
        XCTAssertFalse(NetUtil.isLoopback("192.168.1.1"))
        XCTAssertFalse(NetUtil.isLoopback("8.8.8.8"))
    }

    func testIsPrivateIPAddress() {
        XCTAssertTrue(NetUtil.isPrivateIP("10.0.0.1"))
        XCTAssertTrue(NetUtil.isPrivateIP("172.16.5.10"))
        XCTAssertTrue(NetUtil.isPrivateIP("172.31.255.254"))
        XCTAssertTrue(NetUtil.isPrivateIP("192.168.1.100"))
        XCTAssertFalse(NetUtil.isPrivateIP("172.32.0.1"))
        XCTAssertFalse(NetUtil.isPrivateIP("8.8.8.8"))
        XCTAssertFalse(NetUtil.isPrivateIP("1.1.1.1"))
    }

    func testCIDRMatcherIPv4() throws {
        let matcher = try CIDRMatcher(cidr: "192.168.1.0/24")
        XCTAssertTrue(matcher.contains("192.168.1.1"))
        XCTAssertTrue(matcher.contains("192.168.1.254"))
        XCTAssertFalse(matcher.contains("192.168.2.1"))
        XCTAssertFalse(matcher.contains("10.0.0.1"))
    }

    func testCIDRMatcherOutOfRange() throws {
        let matcher = try CIDRMatcher(cidr: "10.0.0.0/8")
        XCTAssertTrue(matcher.contains("10.254.254.254"))
        XCTAssertFalse(matcher.contains("11.0.0.1"))
        XCTAssertThrowsError(try CIDRMatcher(cidr: "invalid/cidr"))
        XCTAssertThrowsError(try CIDRMatcher(cidr: "10.0.0.0/33"))
    }

    func testExponentialBackoffNextInterval() {
        let backoff = ExponentialBackoff(initialInterval: 1.0, maxInterval: 10.0, multiplier: 2.0)
        XCTAssertEqual(backoff.nextInterval(), 1.0)
        XCTAssertEqual(backoff.nextInterval(), 2.0)
        XCTAssertEqual(backoff.nextInterval(), 4.0)
        XCTAssertEqual(backoff.nextInterval(), 8.0)
    }

    func testExponentialBackoffCapMax() {
        let backoff = ExponentialBackoff(initialInterval: 4.0, maxInterval: 10.0, multiplier: 2.0)
        _ = backoff.nextInterval() // 4
        _ = backoff.nextInterval() // 8
        XCTAssertEqual(backoff.nextInterval(), 10.0) // capped at 10
        XCTAssertEqual(backoff.nextInterval(), 10.0)
    }

    func testExponentialBackoffReset() {
        let backoff = ExponentialBackoff(initialInterval: 1.0, maxInterval: 10.0, multiplier: 2.0)
        _ = backoff.nextInterval()
        _ = backoff.nextInterval()
        backoff.reset()
        XCTAssertEqual(backoff.nextInterval(), 1.0)
    }

    func testRateLimiterAllowsUnderBurst() {
        let limiter = TokenBucketRateLimiter(rate: 10.0, burst: 5.0)
        for _ in 0..<5 {
            XCTAssertTrue(limiter.allow(count: 1.0))
        }
    }

    func testRateLimiterBlocksWhenExhausted() {
        let limiter = TokenBucketRateLimiter(rate: 1.0, burst: 2.0)
        XCTAssertTrue(limiter.allow(count: 1.0))
        XCTAssertTrue(limiter.allow(count: 1.0))
        XCTAssertFalse(limiter.allow(count: 1.0))
    }

    func testGenerateRandomStringLengthAndCharset() {
        let str = StringUtil.randomString(length: 32)
        XCTAssertEqual(str.count, 32)
        let allowed = CharacterSet.alphanumerics
        XCTAssertTrue(str.unicodeScalars.allSatisfy { allowed.contains($0) })
    }

    func testCanonicalHeaderKeyFormatting() {
        XCTAssertEqual(StringUtil.canonicalHeaderKey("content-type"), "Content-Type")
        XCTAssertEqual(StringUtil.canonicalHeaderKey("x-frp-token"), "X-Frp-Token")
        XCTAssertEqual(StringUtil.canonicalHeaderKey("authorization"), "Authorization")
    }
}
