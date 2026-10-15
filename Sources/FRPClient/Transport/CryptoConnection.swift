import Foundation
import CommonCrypto

public final class CryptoConnection: AsyncConnection, @unchecked Sendable {
    private let underlying: any AsyncConnection
    private let key: [UInt8]

    private let readLock = SafeLock()
    private var decCryptor: CCCryptorRef?
    private var ivReceived = false

    private let writeLock = SafeLock()
    private var encCryptor: CCCryptorRef?
    private var ivSent = false

    public init(wrapping underlying: any AsyncConnection, token: String) {
        self.underlying = underlying
        var derivedKey = [UInt8](repeating: 0, count: 16)
        let salt = "frp"
        _ = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            token,
            token.utf8.count,
            salt,
            salt.utf8.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
            64,
            &derivedKey,
            16
        )
        self.key = derivedKey
    }

    deinit {
        readLock.withLock {
            if let dec = decCryptor {
                CCCryptorRelease(dec)
                decCryptor = nil
            }
        }
        writeLock.withLock {
            if let enc = encCryptor {
                CCCryptorRelease(enc)
                encCryptor = nil
            }
        }
    }

    public var isClosed: Bool {
        underlying.isClosed
    }

    public func close() {
        underlying.close()
    }

    public func write(_ data: Data) async throws {
        guard !data.isEmpty else { return }

        // 1. Ensure IV is sent on first write
        let (needsIV, enc) = writeLock.withLock { () -> (Data?, CCCryptorRef) in
            if !ivSent {
                var randomIV = [UInt8](repeating: 0, count: 16)
                _ = SecRandomCopyBytes(kSecRandomDefault, 16, &randomIV)
                var cryptor: CCCryptorRef?
                let status = CCCryptorCreateWithMode(
                    CCOperation(kCCEncrypt),
                    CCMode(kCCModeCFB),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCPadding(ccNoPadding),
                    randomIV,
                    key,
                    16,
                    nil, 0, 0, 0,
                    &cryptor
                )
                if status != kCCSuccess || cryptor == nil {
                    // Fallback or unrecoverable error
                    fatalError("Failed to create AES-CFB encryptor: \(status)")
                }
                self.encCryptor = cryptor
                self.ivSent = true
                return (Data(randomIV), cryptor!)
            }
            return (nil, encCryptor!)
        }

        if let ivData = needsIV {
            try await underlying.write(ivData)
        }

        // 2. Encrypt and write payload
        var ciphertext = [UInt8](repeating: 0, count: data.count)
        var outLen: Int = 0
        let status = writeLock.withLock {
            data.withUnsafeBytes { rawPtr in
                CCCryptorUpdate(enc, rawPtr.baseAddress, data.count, &ciphertext, ciphertext.count, &outLen)
            }
        }
        guard status == kCCSuccess else {
            throw AsyncConnectionError.writeFailed("AES-CFB encryption failed with status \(status)")
        }

        try await underlying.write(Data(ciphertext))
    }

    private func ensureDecrypter() async throws {
        let needsIV = readLock.withLock { !ivReceived }
        if needsIV {
            let ivData = try await underlying.read(exactCount: 16)
            readLock.withLock {
                guard !ivReceived else { return }
                var cryptor: CCCryptorRef?
                let status = CCCryptorCreateWithMode(
                    CCOperation(kCCDecrypt),
                    CCMode(kCCModeCFB),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCPadding(ccNoPadding),
                    [UInt8](ivData),
                    key,
                    16,
                    nil, 0, 0, 0,
                    &cryptor
                )
                if status != kCCSuccess || cryptor == nil {
                    fatalError("Failed to create AES-CFB decryptor: \(status)")
                }
                self.decCryptor = cryptor
                self.ivReceived = true
            }
        }
    }

    public func read(upToCount maxCount: Int) async throws -> Data {
        try await ensureDecrypter()
        let encrypted = try await underlying.read(upToCount: maxCount)
        guard !encrypted.isEmpty else { return Data() }

        var decrypted = [UInt8](repeating: 0, count: encrypted.count)
        var outLen: Int = 0
        let status = readLock.withLock { () -> CCCryptorStatus in
            guard let dec = decCryptor else { return CCCryptorStatus(kCCParamError) }
            return encrypted.withUnsafeBytes { rawPtr in
                CCCryptorUpdate(dec, rawPtr.baseAddress, encrypted.count, &decrypted, decrypted.count, &outLen)
            }
        }
        guard status == kCCSuccess else {
            throw AsyncConnectionError.readFailed("AES-CFB decryption failed with status \(status)")
        }

        return Data(decrypted)
    }

    public func read(exactCount count: Int) async throws -> Data {
        try await ensureDecrypter()
        let encrypted = try await underlying.read(exactCount: count)

        var decrypted = [UInt8](repeating: 0, count: encrypted.count)
        var outLen: Int = 0
        let status = readLock.withLock { () -> CCCryptorStatus in
            guard let dec = decCryptor else { return CCCryptorStatus(kCCParamError) }
            return encrypted.withUnsafeBytes { rawPtr in
                CCCryptorUpdate(dec, rawPtr.baseAddress, encrypted.count, &decrypted, decrypted.count, &outLen)
            }
        }
        guard status == kCCSuccess else {
            throw AsyncConnectionError.readFailed("AES-CFB decryption failed with status \(status)")
        }

        return Data(decrypted)
    }
}
