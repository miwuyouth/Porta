import Foundation
import CryptoKit

public enum FRPAuth {
    /// Generates privilege_key used in FRP token authentication.
    /// Formula: MD5(token + String(timestamp)) in lowercase hex string.
    public static func getAuthKey(token: String, timestamp: Int64) -> String {
        let inputString = "\(token)\(timestamp)"
        let inputData = Data(inputString.utf8)
        let digest = Insecure.MD5.hash(data: inputData)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
