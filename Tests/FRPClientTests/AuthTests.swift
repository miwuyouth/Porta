import XCTest
@testable import FRPClient

final class AuthTests: XCTestCase {
    func testMD5AuthKeyCalculation() {
        let token = "test_token_123"
        let timestamp: Int64 = 1700000000
        // Input string: "test_token_1231700000000"
        let key = FRPAuth.getAuthKey(token: token, timestamp: timestamp)

        XCTAssertEqual(key.count, 32)
        XCTAssertFalse(key.contains(where: { $0.isUppercase }))

        let expected = "9c3f01f51704be37bd4f559763b9203a"
        XCTAssertEqual(key, expected)
    }

    func testEmptyTokenAuthKey() {
        let token = ""
        let timestamp: Int64 = 123456789
        // Input string: "123456789"
        let key = FRPAuth.getAuthKey(token: token, timestamp: timestamp)

        XCTAssertEqual(key.count, 32)
        // MD5 of "123456789" is "25f9e794323b453885f5181f1b624d0b"
        XCTAssertEqual(key, "25f9e794323b453885f5181f1b624d0b")
    }

    func testSpecialCharactersAndUnicodeInToken() {
        let token = "p@$$w0rd_🚀_测试"
        let timestamp: Int64 = 1600000000
        let key1 = FRPAuth.getAuthKey(token: token, timestamp: timestamp)
        let key2 = FRPAuth.getAuthKey(token: token, timestamp: timestamp)

        XCTAssertEqual(key1.count, 32)
        XCTAssertEqual(key1, key2, "Hash must be deterministic")
        XCTAssertFalse(key1.contains(where: { $0.isUppercase }))
    }

    func testBoundaryTimestamps() {
        // Timestamp 0
        let keyZero = FRPAuth.getAuthKey(token: "token", timestamp: 0)
        XCTAssertEqual(keyZero.count, 32)

        // Large Int64 timestamp
        let keyMax = FRPAuth.getAuthKey(token: "token", timestamp: Int64.max)
        XCTAssertEqual(keyMax.count, 32)
    }
}
