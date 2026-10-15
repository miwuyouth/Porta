import Foundation
import CommonCrypto

private final class AsyncMutex: @unchecked Sendable {
    private let lock = SafeLock()
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isLocked = false

    func acquire() async {
        await withCheckedContinuation { continuation in
            let shouldWait = lock.withLock { () -> Bool in
                if isLocked {
                    waiters.append(continuation)
                    return true
                } else {
                    isLocked = true
                    return false
                }
            }
            if !shouldWait {
                continuation.resume()
            }
        }
    }

    func release() {
        let next = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            if !waiters.isEmpty {
                return waiters.removeFirst()
            } else {
                isLocked = false
                return nil
            }
        }
        next?.resume()
    }
}

public final class CryptoConnection: AsyncConnection, @unchecked Sendable {
    private let underlying: any AsyncConnection
    private let key: [UInt8]

    private let readLock = AsyncMutex()
    private var decCryptor: CCCryptorRef?
    private var ivReceived = false

    private let writeLock = AsyncMutex()
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
        if let dec = decCryptor {
            CCCryptorRelease(dec)
            decCryptor = nil
        }
        if let enc = encCryptor {
            CCCryptorRelease(enc)
            encCryptor = nil
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

        await writeLock.acquire()
        defer { writeLock.release() }

        var packet = Data()
        if !ivSent {
            var randomIV = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, 16, &randomIV)
            guard status == errSecSuccess else {
                throw AsyncConnectionError.writeFailed("Failed to generate secure random IV: \(status)")
            }
            var cryptor: CCCryptorRef?
            let createStatus = CCCryptorCreateWithMode(
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
            guard createStatus == kCCSuccess, let c = cryptor else {
                throw AsyncConnectionError.writeFailed("Failed to create AES-CFB encryptor: \(createStatus)")
            }
            self.encCryptor = c
            self.ivSent = true
            packet.append(contentsOf: randomIV)
        }

        guard let enc = encCryptor else {
            throw AsyncConnectionError.writeFailed("Encryptor not initialized")
        }

        var ciphertext = [UInt8](repeating: 0, count: data.count)
        var outLen: Int = 0
        let status = data.withUnsafeBytes { rawPtr in
            CCCryptorUpdate(enc, rawPtr.baseAddress, data.count, &ciphertext, ciphertext.count, &outLen)
        }
        guard status == kCCSuccess else {
            throw AsyncConnectionError.writeFailed("AES-CFB encryption failed with status \(status)")
        }

        packet.append(contentsOf: ciphertext)
        try await underlying.write(packet)
    }

    private func ensureDecrypterUnlocked() async throws {
        guard !ivReceived else { return }
        let ivData = try await underlying.read(exactCount: 16)
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
        guard status == kCCSuccess, let c = cryptor else {
            throw AsyncConnectionError.readFailed("Failed to create AES-CFB decryptor: \(status)")
        }
        self.decCryptor = c
        self.ivReceived = true
    }

    public func read(upToCount maxCount: Int) async throws -> Data {
        await readLock.acquire()
        defer { readLock.release() }

        try await ensureDecrypterUnlocked()
        let encrypted = try await underlying.read(upToCount: maxCount)
        guard !encrypted.isEmpty else { return Data() }

        guard let dec = decCryptor else {
            throw AsyncConnectionError.readFailed("Decryptor not initialized")
        }

        var decrypted = [UInt8](repeating: 0, count: encrypted.count)
        var outLen: Int = 0
        let status = encrypted.withUnsafeBytes { rawPtr in
            CCCryptorUpdate(dec, rawPtr.baseAddress, encrypted.count, &decrypted, decrypted.count, &outLen)
        }
        guard status == kCCSuccess else {
            throw AsyncConnectionError.readFailed("AES-CFB decryption failed with status \(status)")
        }

        return Data(decrypted)
    }

    public func read(exactCount count: Int) async throws -> Data {
        await readLock.acquire()
        defer { readLock.release() }

        try await ensureDecrypterUnlocked()
        let encrypted = try await underlying.read(exactCount: count)

        guard let dec = decCryptor else {
            throw AsyncConnectionError.readFailed("Decryptor not initialized")
        }

        var decrypted = [UInt8](repeating: 0, count: encrypted.count)
        var outLen: Int = 0
        let status = encrypted.withUnsafeBytes { rawPtr in
            CCCryptorUpdate(dec, rawPtr.baseAddress, encrypted.count, &decrypted, decrypted.count, &outLen)
        }
        guard status == kCCSuccess else {
            throw AsyncConnectionError.readFailed("AES-CFB decryption failed with status \(status)")
        }

        return Data(decrypted)
    }
}
